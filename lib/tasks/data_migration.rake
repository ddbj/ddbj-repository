namespace :data_migration do
  # Phase 3 spike scope: import a single BioProject from a D-way XML file.
  # Idempotent on re-run with the same source XML (skips the SubmissionUpdate
  # insert when the prior tail patch is byte-identical to the new baseline);
  # raises on cross-user collision instead of silently re-attributing.
  desc 'Import a single BioProject from a D-way XML file (Phase 3 spike, single record)'
  task :import_bp_from_file, %i[xml_path psub_id user_uid project_type] => :environment do |_, args|
    xml_path     = args.fetch(:xml_path)
    psub_id      = args.fetch(:psub_id)
    user_uid     = args.fetch(:user_uid)
    project_type = args[:project_type].presence || 'primary'

    xml  = File.read(xml_path)
    user = User.find_by!(uid: user_uid)

    record    = BioProject::Converter.new(xml:, project_row: {project_type:}).call
    accession = record.dig('project', 'accession') or
      raise 'XML had no /Project/Project/ProjectID/ArchiveID/@accession; cannot derive accession'

    baseline = [{'op' => 'add', 'path' => '', 'value' => record}]
    patch    = Oj.dump(baseline, mode: :strict)

    Submission.transaction do
      submission = Submission.find_or_create_by!(db: :bioproject, source_id: psub_id) {|s|
        s.user           = user
        s.migration_run_id = SecureRandom.uuid
      }

      if submission.user_id != user.id
        raise "Submission #{psub_id} already exists under user '#{submission.user.uid}'; " \
              "refusing to silently re-attribute to '#{user_uid}'."
      end

      # `update_columns` bypasses the v2-era `validates :ddbj_record, on: :update`
      # constraint — migration-sourced submissions store state in
      # submission_updates patches, not in the ddbj_record blob.
      submission.update_columns(
        canonical_version: 1,
        converter_version: "bp_v3/#{BioProject::Converter::SOURCE_FORMAT}",
        updated_at:        Time.current
      )

      submission.project ||
        Project.create!(
          submission:,
          accession:,
          project_type:,
          status:    :public,
          title:     record.dig('project', 'title')
        )

      last_patch = submission.updates.order(:id).last&.patch
      if last_patch == patch
        puts "Skipped: Submission ##{submission.id} (#{accession}) — baseline patch unchanged"
      else
        submission.updates.create!(
          db:                       'bioproject',
          status:                   :applied,
          actor:                    "migration:#{user_uid}",
          source:                   :migration,
          patch:                    patch,
          patch_canonical_version:  1
        )

        puts "Imported #{accession} → Submission ##{submission.id} (#{submission.updates.count} update[s])"
      end
    end
  end
end
