# frozen_string_literal: true

module BioSample
  # Wraps one BS submission's worth of writes (Submission + N Sample rows
  # + baseline SubmissionUpdate) in a single transaction.
  #
  # Idempotency model (two levels):
  #   - SubmissionUpdate insert + Submission canonical_version / converter_
  #     version / migration_run_id refresh: gated on a real patch byte
  #     difference. Re-running with identical EAV state returns :skipped
  #     and does not append a duplicate baseline patch nor bump
  #     migration_run_id.
  #   - Sample typed-column sync (accession / sample_name / package /
  #     package_group / env_package / taxonomy_id / organism / status /
  #     title / release_date / dist_date / modified_date): ALWAYS runs.
  #     Some of those columns (package_group, env_package, release_date,
  #     dist_date, modified_date) live only on the staging row and never
  #     reach the canonical patch, so gating sync on patch-difference would
  #     permanently strand any staging-side updates to them. (release_date /
  #     dist_date feed the public / three-pole exchange XML; modified_date
  #     is the livelist's `Updated`.) The trade-
  #     off is that curator edits to typed columns survive only until
  #     the next re-import — Phase 6 needs explicit curator-edit-vs-
  #     staging diff handling.
  #
  # Sample identity (sync_samples!) is position-based against the staging
  # ORDER BY smp_id, NOT accession. That handles the 14% of staging
  # samples that have NULL accession (pre-accession drafts). Phase 6
  # should add a `staging_smp_id` column to the samples table for a
  # stable persistent identity that survives re-ordering / staging
  # smp_id renumbering; the spike's position-based sync is correct only
  # while the staging query remains `ORDER BY smp_id` and no inserts
  # land mid-prefix.
  class Importer
    class CrossUserError < StandardError; end

    Result = Data.define(:submission, :outcome) # :created | :updated | :skipped | :no_samples

    def initialize(staging_submission:, user_uid:, migration_run_id:)
      @row              = staging_submission
      @user_uid         = user_uid
      @migration_run_id = migration_run_id
    end

    def call
      return Result.new(submission: nil, outcome: :no_samples) if @row.samples.empty?

      record = Converter.new(submission: @row).call
      user   = User.find_or_create_by!(uid: @user_uid)

      Submission.transaction do
        submission = Submission.find_or_create_by!(db: :biosample, source_id: @row.ssub_id) {|s|
          s.user             = user
          s.migration_run_id = @migration_run_id
        }

        if submission.user_id != user.id
          raise CrossUserError,
                "Submission #{@row.ssub_id} already exists under user '#{submission.user.uid}'; " \
                "refusing to silently re-attribute to '#{@user_uid}'."
        end

        submission.ensure_migration_request!(migration_run_id: @migration_run_id)

        # Sample typed columns ALWAYS sync — they include staging-only
        # fields (package_group, env_package) that never reach the
        # canonical patch, so the patch-difference skip below cannot
        # protect them without permanently stranding staging updates.
        sync_samples!(submission, record)

        # curator_comment is staging-only too: the Converter intentionally
        # does NOT put it into v3 (it's a curator-internal note, not
        # DDBJ Record content), so the patch-difference skip cannot
        # carry it. Always re-stamp.
        if submission.curator_comment != @row.comment
          submission.update_columns(curator_comment: @row.comment)
        end

        # Fast :skipped path: a checksum of the raw converter output. If
        # the source XML hasn't changed meaningfully we short-circuit
        # without paying for a canonicalisation pass (~3 s per BS record
        # at 7 MB scale — the cost that turned a 4060-record re-import
        # sweep into a 3.5-hour run), let alone diff's two. Deliberately
        # "vs last import" rather than "vs current chain", so workbench
        # edits survive an idempotent re-run against an unchanged source.
        source_checksum = Digest::MD5.base64digest(Oj.dump(record, mode: :strict))

        if submission.source_checksum == source_checksum
          submission.update_columns(
            migration_run_id: @migration_run_id,
            updated_at:       Time.current
          )
          return Result.new(submission:, outcome: :skipped)
        end

        # Semantic diff path. First-import: materialised_record is nil →
        # diff({}, record) returns one `add /<top_level_key>` op per
        # top-level key. Re-import unchanged: diff is empty (but the
        # fast path above already caught it). Real shape delta: minimal
        # RFC 6902 ops, or a root snapshot fallback when the diff
        # would descend into a bag-array element or hit any
        # Canonicalizer::Error. safe_prior_materialised swallows
        # MaterialisationFailed so a poisoned historical patch lets
        # the importer self-heal forward.
        prior_record = safe_prior_materialised(submission)
        patch_ops    = compute_patch_ops(prior_record, record, legacy: submission.legacy_chain?)

        if patch_ops.empty?
          # The fast byte-equality check above should normally catch
          # this case, but Canonicalizer.diff can also return [] when
          # prior and current canonicalise to the same form despite
          # differing in non-canonical noise (whitespace, key order
          # not preserved across some intermediate step, etc.). Same
          # stamping: sync_samples! ran, so re-stamp migration_run_id
          # for rollback-grain correctness.
          submission.update_columns(
            migration_run_id: @migration_run_id,
            source_checksum:  source_checksum,
            updated_at:       Time.current
          )
          return Result.new(submission:, outcome: :skipped)
        end

        # The bytes the chain will now replay to. Derived by applying the
        # ops we just computed rather than by re-serialising `record`:
        # it avoids a third canonicalisation, and it asserts the property
        # the chain exists for — replaying it reproduces exactly this.
        new_dump = Oj.dump(DDBJRecord::Canonicalizer.apply(prior_record, patch_ops), mode: :strict)

        submission.update_columns(
          canonical_version: DDBJRecord::Canonicalizer::NUMBER,
          converter_version: "bs_v3/#{Converter::SOURCE_FORMAT}",
          migration_run_id:  @migration_run_id,
          source_checksum:   source_checksum,
          updated_at:        Time.current
        )

        new_update = SubmissionUpdate.create_with_patch!(
          submission:              submission,
          patch_json:              Oj.dump(patch_ops, mode: :strict),
          db:                      'biosample',
          status:                  :applied,
          actor:                   "migration:#{@user_uid}",
          source:                  :migration,
          patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
        )

        # Re-populate the cache that SubmissionUpdate#after_create
        # just nulled, so the NEXT re-import's fast-path checksum
        # check hits without having to replay the chain via
        # materialised_record. prime_cache! holds a row-level lock for
        # the (blob, stamp) write — overkill here (importer is single-
        # threaded per submission) but cheap.
        submission.prime_cache!(bytes: new_dump, update_id: new_update.id)

        Result.new(submission:, outcome: submission.updates.size == 1 ? :created : :updated)
      end
    end

    private

    def safe_prior_materialised(submission)
      submission.materialised_record || {}
    rescue Submission::MaterialisationFailed => e
      Rails.error.report e, context: {submission_id: submission.id, source_id: @row.ssub_id}
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
    # bytes that diff() rejects on re-import; falling through to a
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

    def sync_samples!(submission, record)
      v3_samples       = record.fetch('samples')
      staging_samples  = @row.samples
      existing_samples = submission.samples.order(:id).to_a

      if v3_samples.length != staging_samples.length
        raise "PSUB #{@row.ssub_id}: v3 sample count (#{v3_samples.length}) " \
              "diverges from staging sample count (#{staging_samples.length})"
      end

      v3_samples.zip(staging_samples).each_with_index do |(v3, staging), idx|
        attrs = {
          accession:     v3['accession'],
          sample_name:   v3['alias'],
          status:        map_status(staging.status_id),
          title:         v3['title'],
          package:       v3['package'],
          # NOTE(phase 6 deferral): :package_group is derivable from :package
          # against a versioned catalog snapshot — see staging_client.rb Sample
          # Data class comment. Persisting staging's value as-is for now so we
          # have an audit anchor when the derivation lands.
          package_group: staging.package_group,
          env_package:   staging.env_package,
          release_date:  staging.release_date,
          dist_date:     staging.dist_date,
          modified_date: staging.modified_date,
          taxonomy_id:   v3.dig('organism', 'taxonomy_id'),
          organism:      v3.dig('organism', 'name')
        }

        if (existing = existing_samples[idx])
          existing.update!(attrs)
        else
          submission.samples.create!(attrs)
        end
      end

      # Drop trailing Sample rows whose position is no longer in the
      # staging snapshot (curator removed a sample in D-way). Without
      # this the typed-column view drifts away from the materialised v3
      # record forever.
      existing_samples[v3_samples.length..].to_a.each(&:destroy)
    end

    # BS staging is entirely on the new 5xxx Lifecycleable codes (verified
    # against staging: 0 rows have legacy status_id=700, unlike BP). So
    # the BP `when 700` arm is intentionally absent here.
    def map_status(legacy_status_id)
      case legacy_status_id
      when 5500 then :public
      when 5400 then :private
      when 5600 then :withdrawn
      when 5700 then :canceled
      when 5800 then :permanently_suppressed
      when 5900 then :temporarily_suppressed
      else           :curating
      end
    end
  end
end
