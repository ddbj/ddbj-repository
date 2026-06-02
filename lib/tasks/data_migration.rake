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
    puts "[#{result.outcome}] PSUB #{args[:psub_id]} → Submission ##{result.submission&.id}"
  end

  # Batch import every BioProject in the staging mass schema.
  #
  # Run locally via an SSH local-forward tunnel:
  #
  #   ssh -L 54301:172.19.15.12:54301 a012 -N &
  #   DWAY_DB_PASSWORD=... bin/rails 'data_migration:import_bp_batch[100]'
  #
  # Resume after a crash by passing the last successfully-processed PSUB:
  #
  #   bin/rails 'data_migration:import_bp_batch[100,migration,PSUB000503]'
  #
  # The optional `limit` caps the run; `user_uid` is the fallback owner
  # when a row has no submitter_id (rare); `after` resumes from the next
  # PSUB after the given one.
  desc 'Batch-import BioProjects from D-way staging via SSH tunnel'
  task :import_bp_batch, %i[limit user_uid after] => :environment do |_, args|
    limit            = args[:limit].presence&.to_i
    user_uid         = args[:user_uid].presence || 'migration'
    after            = args[:after].presence
    migration_run_id = SecureRandom.uuid

    counters = Hash.new(0)
    client   = BioProject::StagingClient.new

    begin
      psub_ids = client.submission_ids(limit:, after:)
      total    = psub_ids.size

      puts "Starting batch (#{total} candidate[s], migration_run_id=#{migration_run_id}, after=#{after || '-'})"

      psub_ids.each_with_index do |psub_id, idx|
        begin
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

          counters[importer.call.outcome] += 1
        rescue PG::ConnectionBad, PG::UnableToSend, ActiveRecord::ConnectionNotEstablished => e
          # Connection-level failure: every subsequent row would also fail.
          # Abort so the operator notices immediately rather than amassing
          # spurious `failed=N` lines.
          warn "Connection lost at PSUB #{psub_id} (#{idx + 1}/#{total}): #{e.class}: #{e.message}"
          raise
        rescue BioProject::Importer::CrossUserError => e
          counters[:cross_user] += 1
          warn "[#{psub_id}] CROSS-USER: #{e.message}"
        rescue StandardError => e
          counters[:failed] += 1
          trace = e.backtrace&.first(3)&.join("\n  ") || '(no backtrace)'
          warn "[#{psub_id}] FAIL: #{e.class}: #{e.message}\n  #{trace}"
        ensure
          if ((idx + 1) % 100).zero? || idx + 1 == total
            puts "[#{idx + 1}/#{total}] last=#{psub_id} " + counters.map {|k, v| "#{k}=#{v}" }.join(' ')
          end
        end
      end
    ensure
      client.close
    end

    puts 'Done. ' + counters.map {|k, v| "#{k}=#{v}" }.join(' ')
  end
end
