# frozen_string_literal: true

module BioSample
  # Wraps one BS submission's worth of writes (Submission + N Sample rows
  # + baseline SubmissionUpdate) in a single transaction. Mirrors
  # BioProject::Importer's idempotency contract: re-running with the same
  # ssub_id + identical EAV state is a no-op (the baseline patch is
  # byte-identical to the prior tail), cross-user re-attribution raises,
  # and Sample rows are refreshed only when the patch is actually new
  # (so curator edits survive byte-identical re-imports).
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

        sync_samples!(submission, record)

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
      existing_by_accession = submission.samples.index_by(&:accession)

      record.fetch('samples').each do |s|
        attrs = {
          accession:   s['accession'],
          sample_name: s['alias'],
          status:      map_status(@row.samples.find {|x| x.accession == s['accession'] }&.status_id),
          title:       s['title'],
          package:     s['package'],
          taxonomy_id: s.dig('organism', 'taxonomy_id'),
          organism:    s.dig('organism', 'name')
        }

        if (existing = existing_by_accession[s['accession']])
          existing.update!(attrs)
        else
          submission.samples.create!(attrs)
        end
      end
    end

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
