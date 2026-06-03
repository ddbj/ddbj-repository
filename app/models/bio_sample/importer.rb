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
  #     title): ALWAYS runs. Some of those columns (package_group,
  #     env_package) live only on the staging row and never reach the
  #     canonical patch, so gating sync on patch-difference would
  #     permanently strand any staging-side updates to them. The trade-
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
      patch  = Oj.dump([{'op' => 'add', 'path' => '', 'value' => record}], mode: :strict)

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

        # Sample typed columns ALWAYS sync — they include staging-only
        # fields (package_group, env_package) that never reach the
        # canonical patch, so the patch-byte-equality skip below cannot
        # protect them without permanently stranding staging updates.
        sync_samples!(submission, record)

        prior_patch = submission.updates.order(:id).last&.patch&.b

        if prior_patch == patch.b
          return Result.new(submission:, outcome: :skipped)
        end

        submission.update_columns(
          canonical_version: 1,
          converter_version: "bs_v3/#{Converter::SOURCE_FORMAT}",
          migration_run_id:  @migration_run_id,
          updated_at:        Time.current
        )

        submission.updates.create!(
          db:                       'biosample',
          status:                   :applied,
          actor:                    "migration:#{@user_uid}",
          source:                   :migration,
          patch:                    patch,
          patch_canonical_version:  1
        )

        Result.new(submission:, outcome: submission.updates.size == 1 ? :created : :updated)
      end
    end

    private

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
          package_group: staging.package_group,
          env_package:   staging.env_package,
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
