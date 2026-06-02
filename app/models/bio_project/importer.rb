# frozen_string_literal: true

module BioProject
  # Wraps one BioProject's worth of writes (Submission + Project + baseline
  # SubmissionUpdate) in a single transaction. Shared between the file-based
  # spike rake (`import_bp_from_file`) and the batch rake
  # (`import_bp_batch`).
  #
  # Idempotency contract:
  #   - Re-running with the same psub_id + identical XML is a no-op (the
  #     baseline patch is byte-identical to the prior tail, so the
  #     SubmissionUpdate insert is skipped).
  #   - Re-running with a different user_uid against an existing Submission
  #     raises CrossUserError; we never silently re-attribute.
  #   - Migration runs share a per-run UUID via migration_run_id so a bad
  #     batch can be rolled back as a unit.
  class Importer
    class CrossUserError < StandardError; end

    Result = Data.define(:submission, :outcome) # outcome: :created | :updated | :skipped | :no_accession

    def initialize(psub_id:, xml:, user_uid:, project_type:, migration_run_id:, status: nil)
      @psub_id          = psub_id
      @xml              = xml
      @user_uid         = user_uid
      @project_type     = project_type
      @migration_run_id = migration_run_id
      @status           = status
    end

    def call
      record    = Converter.new(xml: @xml, project_row: {project_type: @project_type}).call
      accession = record.dig('project', 'accession')

      # Legacy / withdrawn submissions in D-way often have an empty
      # `<ArchiveID />` even when status_id says "public". Phase 6 will
      # revisit the policy (fall back to EAV, hold for curator review,
      # etc.); for the spike just skip with a distinct outcome so the
      # batch summary stays meaningful.
      return Result.new(submission: nil, outcome: :no_accession) unless accession

      user = User.find_or_create_by!(uid: @user_uid)

      patch = Oj.dump([{'op' => 'add', 'path' => '', 'value' => record}], mode: :strict)

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

        # `update_columns` bypasses the v2-era `validates :ddbj_record,
        # on: :update` — migration-sourced submissions store state in
        # submission_updates patches, not in the ddbj_record blob.
        submission.update_columns(
          canonical_version: 1,
          converter_version: "bp_v3/#{Converter::SOURCE_FORMAT}",
          updated_at:        Time.current
        )

        project = submission.project ||
                  Project.create!(submission:, accession:, project_type: @project_type)

        project.update!(
          accession:    accession,
          project_type: @project_type,
          status:       map_status(@status),
          title:        record.dig('project', 'title')
        )

        # Force ASCII-8BIT on both sides — PG returns bytea as ASCII-8BIT
        # while Oj.dump returns UTF-8, and Ruby's String#== treats them as
        # unequal whenever any byte is >= 0x80 even when the bytes match.
        prior_patch = submission.updates.order(:id).last&.patch&.b
        if prior_patch == patch.b
          Result.new(submission:, outcome: :skipped)
        else
          submission.updates.create!(
            db:                       'bioproject',
            status:                   :applied,
            actor:                    "migration:#{@user_uid}",
            source:                   :migration,
            patch:                    patch,
            patch_canonical_version:  1
          )
          Result.new(submission:, outcome: submission.updates.size == 1 ? :created : :updated)
        end
      end
    end

    private

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
