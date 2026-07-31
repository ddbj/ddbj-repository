# frozen_string_literal: true

module BioProject
  # Wraps one BioProject's worth of writes (Submission + Project + baseline
  # SubmissionUpdate) in a single transaction. Shared between the file-based
  # spike rake (`import_bp_from_file`) and the batch rake
  # (`import_bp_batch`).
  #
  # Idempotency contract:
  #   - Re-running with the same psub_id + identical XML is a true no-op:
  #     find_or_create_by! reuses the existing row and no further writes
  #     happen. updated_at / migration_run_id / most Project columns are
  #     untouched on the :skipped path. The exception is release_date /
  #     dist_date / modified_date (D-way lifecycle facts consumed by the
  #     three-pole exchange XML and the livelist): they are non-curator,
  #     non-chain metadata and sync on every run so a re-import backfills
  #     them onto already-imported rows — see the sync just below
  #     ensure_migration_request!.
  #   - Re-running with a different user_uid against an existing Submission
  #     raises CrossUserError; we never silently re-attribute.
  #   - When a new patch IS appended (XML actually changed), Submission and
  #     Project columns are refreshed AND migration_run_id is restamped to
  #     the current run so a bad batch can be `Submission.where(
  #     migration_run_id: <bad_run>).destroy_all`-d. NB: the same UUID does
  #     NOT yet propagate to submission_updates rows — adding the column +
  #     join-based rollback is a Phase 6 schema-change task.
  class Importer
    class CrossUserError < StandardError; end

    Result = Data.define(:submission, :outcome) # outcome: :created | :updated | :skipped | :no_accession

    def initialize(psub_id:, xml:, user_uid:, project_type:, migration_run_id:, accession: nil, status: nil, release_date: nil, dist_date: nil, modified_date: nil)
      @psub_id          = psub_id
      @xml              = xml
      @user_uid         = user_uid
      @project_type     = project_type
      @accession        = accession
      @migration_run_id = migration_run_id
      @status           = status
      @release_date     = release_date
      @dist_date        = dist_date
      @modified_date    = modified_date
    end

    def call
      record    = Converter.new(xml: @xml, project_row: {project_type: @project_type, accession: @accession}).call
      accession = record.dig('project', 'accession')

      # `:no_accession` fires when the staging DB column
      # (`project.project_id_prefix || project_id_counter`) is blank.
      # Real cohort: 277 staging rows, 943 production rows. These are
      # legacy / withdrawn submissions that genuinely lack an accession
      # at the canonical source. Curator review (the "excluded data list"
      # workflow) decides per-row whether to skip permanently or recover.
      # XML <ArchiveID> is intentionally NOT a fallback source — see
      # converter.rb accession comment; in short, XML is user-editable
      # and a 2026-06-03 prod scan found zero rows where XML carried a
      # valid accession against an empty DB column.
      return Result.new(submission: nil, outcome: :no_accession) unless accession

      user = User.find_or_create_by!(uid: @user_uid)

      Submission.transaction do
        submission = Submission.find_or_create_by!(db: :bioproject, source_id: @psub_id) {|s|
          s.user             = user
          s.migration_run_id = @migration_run_id
        }

        if submission.user_id != user.id
          raise CrossUserError,
                "Submission #{@psub_id} already exists under user '#{submission.user.uid}'; " \
                "refusing to silently re-attribute to '#{@user_uid}'."
        end

        submission.ensure_migration_request!(migration_run_id: @migration_run_id)

        # Project row + its D-way lifecycle dates. release_date (初回公開)
        # and dist_date (再公開) feed the three-pole exchange XML's
        # eAdded/eUpdated action; modified_date (最終更新日) is the livelist's
        # `Updated` column. They are neither curator-edited nor part of the
        # XML-diffed materialised chain, so — unlike status / title below —
        # sync them on EVERY run, including the fast-skip path, or a
        # re-import would never backfill an already-imported row. Ensured
        # here (not on the change path) precisely so the skip path sees it.
        project = submission.project || Project.create!(submission:, accession:, project_type: @project_type)
        project.update_columns(release_date: @release_date, dist_date: @dist_date, modified_date: @modified_date)

        # hold_date is a projection of the record we just built (see
        # Submission#sync_hold_date!). Synced on every run for the same
        # reason as the dates above: the fast-skip path must still backfill
        # a row imported before the projection existed.
        submission.sync_hold_date!(record)

        # Fast :skipped path: a checksum of the raw converter output. If
        # the source XML hasn't changed meaningfully we short-circuit
        # without paying for a canonicalisation pass, let alone diff's two.
        # Deliberately "vs last import" rather than "vs current chain", so
        # curator edits made through the workbench survive an idempotent
        # re-run against an unchanged D-way source.
        source_checksum = Digest::MD5.base64digest(Oj.dump(record, mode: :strict))

        if submission.source_checksum == source_checksum
          return Result.new(submission:, outcome: :skipped)
        end

        # Semantic diff path. First-import: diff({}, record) →
        # per-top-level-key add ops. Real shape delta: minimal RFC
        # 6902 ops or root-snapshot fallback on bag-descent / other
        # Canonicalizer::Error. safe_prior_materialised swallows
        # MaterialisationFailed so a poisoned historical patch lets
        # the importer self-heal forward.
        prior_record = safe_prior_materialised(submission)
        patch_ops    = compute_patch_ops(prior_record, record, legacy: submission.legacy_chain?)

        if patch_ops.empty?
          # Nothing to record, but remember what we just compared against
          # so the next run takes the cheap path.
          submission.update_columns(source_checksum:)

          return Result.new(submission:, outcome: :skipped)
        end

        # The bytes the chain will now replay to. Derived by applying the
        # ops we just computed rather than by re-serialising `record`:
        # it avoids a third canonicalisation, and it asserts the property
        # the chain exists for — replaying it reproduces exactly this.
        new_dump = Oj.dump(DDBJRecord::Canonicalizer.apply(prior_record, patch_ops), mode: :strict)

        # `update_columns` bypasses the v2-era `validates :ddbj_record,
        # on: :update` — migration-sourced submissions store state in
        # submission_updates patches, not in the ddbj_record blob.
        submission.update_columns(
          canonical_version: DDBJRecord::Canonicalizer::NUMBER,
          converter_version: "bp_v3/#{Converter::SOURCE_FORMAT}",
          migration_run_id:  @migration_run_id,
          source_checksum:   source_checksum,
          updated_at:        Time.current
        )

        # Materialised-snapshot columns (status / title, plus accession /
        # project_type re-affirmed): refreshed only on real updates so
        # curator-edited fields survive byte-identical re-imports. Phase 6
        # needs explicit curator-edit-vs-import diff to handle the case
        # where XML diverges AFTER a curator touched the row. (release_date
        # / dist_date are handled above, unconditionally, on purpose.)
        project.update!(
          accession:    accession,
          project_type: @project_type,
          status:       map_status(@status),
          title:        record.dig('project', 'title')
        )

        new_update = SubmissionUpdate.create_with_patch!(
          submission:              submission,
          patch_json:              Oj.dump(patch_ops, mode: :strict),
          db:                      'bioproject',
          status:                  :applied,
          actor:                   "migration:#{@user_uid}",
          source:                  :migration,
          patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
        )

        # Re-populate the cache that SubmissionUpdate#after_create
        # just nulled, so the NEXT re-import's fast-path checksum
        # check hits without paying for chain replay + canonicalize × 2.
        submission.prime_cache!(bytes: new_dump, update_id: new_update.id)

        Result.new(submission:, outcome: submission.updates.size == 1 ? :created : :updated)
      end
    end

    private

    def safe_prior_materialised(submission)
      submission.materialised_record || {}
    rescue Submission::MaterialisationFailed => e
      # A poisoned patch is a fact about THIS submission, and treating
      # its prior state as empty is how the importer heals forward.
      #
      # An unreachable store is not that fact. It makes every chain read
      # as empty, and "empty" here means "write a root snapshot built
      # from D-way" — which silently discards every curator edit the
      # chain was carrying. A store that flaps rather than stays down
      # then lets the upload succeed, and the run reports :updated.
      #
      # So it goes back up, where SyncJob stops the sweep.
      raise if StorageFailure === e

      Rails.error.report e, context: {submission_id: submission.id, source_id: @psub_id}
      {}
    end

    # First import (empty prior) → single `add /` root snapshot, so
    # volatile fields (/schema_version, /provenance, ...) reach the
    # chain. Subsequent semantic-diff updates preserve
    # them via the diff-strips-but-apply-keeps asymmetry documented
    # on Submission#append_update!. Going through Canonicalizer.diff
    # for the empty-prior case would strip volatiles from both sides
    # — the chain would then replay to a record SMALLER than what
    # the importer's bytea cache holds, surfacing as a divergence
    # between materialised_record (cache) and materialise_at(past)
    # (pure replay) on the admin show page.
    #
    # Non-empty prior → semantic diff. The rescue catches the full
    # Canonicalizer::Error hierarchy (BagPatchPathError plus
    # ControlCharacterError / NumberGuard / SequenceCodec /
    # OrderedEmptyElement / UnsupportedValue) — those come from the
    # canonicalize pass diff() runs on BOTH sides. apply() is pure
    # RFC 6902 with no validation, so an earlier baseline can carry
    # bytes diff() rejects on re-import; falling through to a
    # root-`replace` snapshot keeps a one-off staging bug from
    # becoming a permanent :failed row.
    # Root snapshots carry the CANONICAL tree, not the raw converter
    # output. `diff` emits array indices into the canonical ordering while
    # `apply` is pure RFC 6902 against whatever is stored, so a baseline in
    # converter order leaves every later patch pointing at the wrong
    # element of a keyed array — silently, and only where the two orders
    # happen to differ. See Canonicalizer#canonical_tree.
    def compute_patch_ops(prior, current, legacy: false)
      return [{'op' => 'add', 'path' => '', 'value' => canonical(current)}] if prior.empty?

      # A pre-v2 chain stored its baseline in raw converter order, so a
      # positional diff against it would name the wrong element of a keyed
      # array. Replace the record wholesale instead — the same heal
      # Submission#append_update! performs, and needed here more: the
      # importers hold the v1 corpus, and a re-import is what runs over it.
      return [{'op' => 'replace', 'path' => '', 'value' => canonical(current)}] if legacy

      DDBJRecord::Canonicalizer.diff(prior, current)
    rescue DDBJRecord::Canonicalizer::Error
      [{'op' => 'replace', 'path' => '', 'value' => canonical(current)}]
    end

    # The rescue above fires on inputs `canonicalize` itself rejects, in
    # which case there is no canonical form to fall back to and the raw
    # tree is all we can store.
    def canonical(record)
      DDBJRecord::Canonicalizer.canonical_tree(record)
    rescue DDBJRecord::Canonicalizer::Error
      record
    end

    # Stand-in for the proper Spike 0.8 mapping table. status_id 700 was the
    # legacy "public" code and dominates the staging set (>99% of rows).
    # Everything else falls back to `:curating` as a safe halfway state —
    # the curator can re-classify after import. Phase 6 will replace this
    # with the canonical 5xxx mapping.
    def map_status(legacy_status_id)
      case legacy_status_id
      when 700, 5500 then :public
      when 5400      then :private
      when 5600      then :withdrawn
      when 5700      then :canceled
      when 5800      then :permanently_suppressed
      when 5900      then :temporarily_suppressed
      else                :curating
      end
    end
  end
end
