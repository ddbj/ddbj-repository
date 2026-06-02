namespace :data_migration do
  desc 'Import a single BioProject from a D-way XML file (spike, single record)'
  task :import_bp_from_file, %i[xml_path psub_id user_uid project_type] => :environment do |_, args|
    importer = BioProject::Importer.new(
      psub_id:          args.fetch(:psub_id),
      xml:              File.read(args.fetch(:xml_path)),
      user_uid:         args.fetch(:user_uid),
      project_type:     args[:project_type].presence || 'primary',
      migration_run_id: SecureRandom.uuid
    )

    result = importer.call
    puts "[#{result.outcome}] PSUB #{args[:psub_id]} → Submission ##{result.submission.id}"
  end

  # Batch import every BioProject in the staging mass schema.
  #
  # Run locally via an SSH local-forward tunnel:
  #
  #   ssh -L 54301:172.19.15.12:54301 a012 -N &
  #   DWAY_DB_PASSWORD=... bin/rails 'data_migration:import_bp_batch[100]'
  #
  # The optional `limit` arg caps the run for incremental rollouts. Skip
  # with `data_migration:import_bp_batch` to import everything.
  #
  # The task is idempotent: a re-run resumes where the prior crashed and
  # skips submissions whose baseline patch is byte-identical.
  desc 'Batch-import BioProjects from D-way staging via SSH tunnel'
  task :import_bp_batch, %i[limit user_uid] => :environment do |_, args|
    limit            = args[:limit].presence&.to_i
    user_uid         = args[:user_uid].presence || 'migration'
    migration_run_id = SecureRandom.uuid

    client    = BioProject::StagingClient.new
    psub_ids  = client.submission_ids(limit: limit)
    total     = psub_ids.size
    counters  = Hash.new(0)

    puts "Starting batch (#{total} candidate[s], migration_run_id=#{migration_run_id})"

    psub_ids.each_with_index do |psub_id, idx|
      row = client.fetch(psub_id)

      if row.nil? || row.xml.blank?
        counters[:no_xml] += 1
        next
      end

      importer = BioProject::Importer.new(
        psub_id:          row.psub_id,
        xml:              row.xml,
        user_uid:         row.submitter_id || user_uid,
        project_type:     row.project_type,
        status:           row.status_id,
        migration_run_id: migration_run_id
      )

      result = importer.call
      counters[result.outcome] += 1

      if ((idx + 1) % 100).zero? || idx + 1 == total
        puts "[#{idx + 1}/#{total}] " + counters.map {|k, v| "#{k}=#{v}" }.join(' ')
      end
    rescue StandardError => e
      counters[:failed] += 1
      warn "[#{psub_id}] FAIL: #{e.class}: #{e.message}"
    end

    client.close

    puts 'Done. ' + counters.map {|k, v| "#{k}=#{v}" }.join(' ')
  end
end
