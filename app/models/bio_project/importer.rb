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
  #     happen. updated_at / migration_run_id / Project columns are
  #     untouched on the :skipped path.
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

    def initialize(psub_id:, xml:, user_uid:, project_type:, migration_run_id:, accession: nil, status: nil)
      @psub_id          = psub_id
      @xml              = xml
      @user_uid         = user_uid
      @project_type     = project_type
      @accession        = accession
      @migration_run_id = migration_run_id
      @status           = status
    end

    def call
      record    = Converter.new(xml: @xml, project_row: {project_type: @project_type, accession: @accession}).call
      accession = record.dig('project', 'accession')

      # `:no_accession` fires when BOTH the staging DB column
      # (`project.project_id_prefix || project_id_counter`) AND the XML
      # `<ArchiveID/>` are blank — see Converter precedence at line 173.
      # Real cohort: 277 staging rows, 943 production rows. These are
      # legacy / withdrawn submissions that genuinely lack an accession
      # at the canonical source. Curator review (the "excluded data list"
      # workflow) decides per-row whether to skip permanently or recover.
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

        # Semantic diff against the prior materialised state when
        # possible. First-import path: materialised_record is nil →
        # diff({}, record) returns one `add /<top_level_key>` op per
        # top-level key (NOT a single root op — JsonDiff decomposes
        # the missing-everything baseline). Re-import of an unchanged
        # record: diff is empty → :skipped. Real shape delta: minimal
        # RFC 6902 ops.
        #
        # compute_patch_ops falls back to a root-level snapshot when
        # the structural diff (a) would descend into a bag-array
        # element (publications, grants, attributes etc. default to
        # bag at any intermediate prefix) or (b) hits any other
        # Canonicalizer::Error. safe_prior_materialised swallows
        # MaterialisationFailed so a poisoned historical patch lets
        # the importer self-heal forward instead of permanently
        # failing every re-import for that submission.
        prior_record = safe_prior_materialised(submission)
        patch_ops    = compute_patch_ops(prior_record, record)

        if patch_ops.empty?
          return Result.new(submission:, outcome: :skipped)
        end

        # `update_columns` bypasses the v2-era `validates :ddbj_record,
        # on: :update` — migration-sourced submissions store state in
        # submission_updates patches, not in the ddbj_record blob.
        submission.update_columns(
          canonical_version: 1,
          converter_version: "bp_v3/#{Converter::SOURCE_FORMAT}",
          migration_run_id:  @migration_run_id,
          updated_at:        Time.current
        )

        project = submission.project ||
                  Project.create!(submission:, accession:, project_type: @project_type)

        # Project columns track the materialised record's snapshot; refreshed
        # only on real updates so curator-edited fields survive byte-identical
        # re-imports. Phase 6 needs explicit curator-edit-vs-import diff to
        # handle the case where XML diverges AFTER a curator touched the row.
        project.update!(
          accession:    accession,
          project_type: @project_type,
          status:       map_status(@status),
          title:        record.dig('project', 'title')
        )

        submission.updates.create!(
          db:                      'bioproject',
          status:                  :applied,
          actor:                   "migration:#{@user_uid}",
          source:                  :migration,
          patch:                   Oj.dump(patch_ops, mode: :strict),
          patch_canonical_version: 1
        )

        Result.new(submission:, outcome: submission.updates.size == 1 ? :created : :updated)
      end
    end

    private

    def safe_prior_materialised(submission)
      submission.materialised_record || {}
    rescue Submission::MaterialisationFailed => e
      Rails.error.report e, context: {submission_id: submission.id, source_id: @psub_id}
      {}
    end

    # Catches the full Canonicalizer::Error hierarchy, not just
    # BagPatchPathError. The other reachable subclasses come from the
    # Normalizer / NumberGuard / SequenceCodec / ArraySorter pass that
    # diff() runs on BOTH sides. Apply, by contrast, is pure RFC 6902 —
    # so a baseline patch from the pre-this-commit code path can carry
    # bytes diff() rejects on the very next re-import. Without this
    # widened rescue any such mismatch rolls the whole importer
    # transaction back, turning a one-off staging bug into a permanent
    # :failed row.
    def compute_patch_ops(prior, current)
      DDBJRecord::Canonicalizer.diff(prior, current)
    rescue DDBJRecord::Canonicalizer::Error
      op = prior.empty? ? 'add' : 'replace'
      [{'op' => op, 'path' => '', 'value' => current}]
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
