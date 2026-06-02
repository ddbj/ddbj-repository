namespace :data_migration do
  desc 'Import a single BioProject from a D-way XML file (Phase 3 spike scope; single record)'
  task :import_bp_from_file, %i[xml_path user_uid project_type] => :environment do |_, args|
    xml_path     = args.fetch(:xml_path)
    user_uid     = args.fetch(:user_uid)
    project_type = args[:project_type].presence || 'primary'

    xml  = File.read(xml_path)
    user = User.find_by!(uid: user_uid)

    record    = BioProject::Converter.new(xml:, project_row: {project_type:}).call
    accession = record.dig('project', 'accession') or
      raise 'XML had no /Project/Project/ProjectID/ArchiveID/@accession; cannot derive source_id'

    submission = Submission.find_or_create_by!(db: :bioproject, source_id: accession) {|s|
      s.user              = user
      s.canonical_version = 1
      s.converter_version = "bp_v3/#{BioProject::Converter::SOURCE_FORMAT}"
    }

    submission.project ||
      Project.create!(
        submission:,
        accession:,
        project_type:,
        status:    :public,
        title:     record.dig('project', 'title')
      )

    baseline = [{'op' => 'add', 'path' => '', 'value' => record}]

    submission.updates.create!(
      db:                       'bioproject',
      status:                   :applied,
      actor:                    "migration:#{user_uid}",
      source:                   :migration,
      patch:                    Oj.dump(baseline, mode: :strict),
      patch_canonical_version:  1
    )

    puts "Imported #{accession} → Submission ##{submission.id} (#{submission.updates.count} update[s])"
  end
end
