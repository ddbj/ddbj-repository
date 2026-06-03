require 'csv' # used by dump_excluded_* tasks; csv stopped being a default gem in Ruby 3.4

namespace :data_migration do
  # Spike utility: single-record import from a local XML file. accession
  # is REQUIRED — XML <ArchiveID> is no longer treated as an accession
  # source (it is freely editable and the 2026-06-03 prod scan showed
  # zero rows actually needed it). Without an accession the row would
  # land as :no_accession.
  desc 'Import a single BioProject from a D-way XML file (spike, single record)'
  task :import_bp_from_file, %i[xml_path psub_id user_uid accession project_type] => :environment do |_, args|
    importer = BioProject::Importer.new(
      psub_id:          args.fetch(:psub_id),
      xml:              File.read(args.fetch(:xml_path)),
      user_uid:         args.fetch(:user_uid),
      accession:        args[:accession].presence,
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
            accession:        row.accession,
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

  # Single-BS spike entry: pulls one submission from staging biosample.mass,
  # creates Submission + N Sample rows + baseline SubmissionUpdate.
  #
  #   ssh -L 54301:172.19.15.12:54301 a012 -N &
  #   DWAY_DB_PASSWORD=... bin/rails 'data_migration:import_bs[SSUB002065]'
  desc 'Import a single BioSample submission from D-way staging (spike, single record)'
  task :import_bs, %i[ssub_id user_uid] => :environment do |_, args|
    ssub_id   = args.fetch(:ssub_id)
    fallback  = args[:user_uid].presence || 'migration'
    run_id    = SecureRandom.uuid

    client = BioSample::StagingClient.new
    begin
      row = client.fetch(ssub_id) or raise "SSUB #{ssub_id} not found in staging"

      importer = BioSample::Importer.new(
        staging_submission: row,
        user_uid:           row.submitter_id || fallback,
        migration_run_id:   run_id
      )

      result = importer.call
      puts "[#{result.outcome}] SSUB #{ssub_id} → Submission ##{result.submission&.id} " \
           "(#{result.submission&.samples&.count} sample[s])"
    ensure
      client.close
    end
  end

  # Batch import every BioSample submission in the staging mass schema.
  # Mirrors data_migration:import_bp_batch — same hardening pattern
  # (PG::ConnectionBad re-raise to abort on dropped tunnel, dedicated
  # `:cross_user` counter, progress emitted inside `ensure`, `after:`
  # cursor for resume, full lifecycle inside begin/ensure so client.close
  # always runs).
  #
  #   ssh -L 54301:172.19.15.12:54301 a012 -N &
  #   DWAY_DB_PASSWORD=... bin/rails 'data_migration:import_bs_batch[100]'
  #
  # Resume: bin/rails 'data_migration:import_bs_batch[100,migration,SSUB001234]'
  desc 'Batch-import BioSamples from D-way staging via SSH tunnel'
  task :import_bs_batch, %i[limit user_uid after] => :environment do |_, args|
    limit            = args[:limit].presence&.to_i
    user_uid         = args[:user_uid].presence || 'migration'
    after            = args[:after].presence
    migration_run_id = SecureRandom.uuid

    counters = Hash.new(0)
    client   = BioSample::StagingClient.new

    begin
      ssub_ids = client.submission_ids(limit:, after:)
      total    = ssub_ids.size

      puts "Starting BS batch (#{total} candidate[s], migration_run_id=#{migration_run_id}, after=#{after || '-'})"

      ssub_ids.each_with_index do |ssub_id, idx|
        begin
          row = client.fetch(ssub_id)

          if row.nil?
            counters[:missing] += 1
            next
          end

          importer = BioSample::Importer.new(
            staging_submission: row,
            user_uid:           row.submitter_id || user_uid,
            migration_run_id:   migration_run_id
          )

          counters[importer.call.outcome] += 1
        rescue PG::ConnectionBad, PG::UnableToSend, ActiveRecord::ConnectionNotEstablished => e
          warn "Connection lost at SSUB #{ssub_id} (#{idx + 1}/#{total}): #{e.class}: #{e.message}"
          raise
        rescue BioSample::Importer::CrossUserError => e
          counters[:cross_user] += 1
          warn "[#{ssub_id}] CROSS-USER: #{e.message}"
        rescue StandardError => e
          counters[:failed] += 1
          trace = e.backtrace&.first(3)&.join("\n  ") || '(no backtrace)'
          warn "[#{ssub_id}] FAIL: #{e.class}: #{e.message}\n  #{trace}"
        ensure
          if ((idx + 1) % 100).zero? || idx + 1 == total
            puts "[#{idx + 1}/#{total}] last=#{ssub_id} " + counters.map {|k, v| "#{k}=#{v}" }.join(' ')
          end
        end
      end
    ensure
      client.close
    end

    puts 'Done. ' + counters.map {|k, v| "#{k}=#{v}" }.join(' ')
  end

  # Dump excluded BP submissions — curator-review CSV.
  #
  # "Excluded" means the regular import_bp_batch pipeline would silently
  # drop the row. Three reasons:
  #   - no_project_row: in mass.submission but not in mass.project
  #     (filtered out by the INNER JOIN in `submission_ids`)
  #   - no_accession:   project row present but project_id_prefix +
  #                     project_id_counter is empty AND XML <ArchiveID/>
  #                     is also blank (DB-column-as-source-of-truth)
  #   - no_xml:         project row present but mass.xml has no content
  #
  # The query runs entirely in staging — no ddbj-repository writes happen.
  # Run from PRODUCTION app container to scan the production D-way data
  # (the staging snapshot is a subset and misses ~half the rows):
  #
  #   bin/kamal app exec -d production \
  #     'DWAY_PGHOST=172.19.15.11 DWAY_DB_PASSWORD=... \
  #      bin/rails data_migration:dump_excluded_bp[tmp/excluded-bp.csv]'
  #
  # Locally via SSH tunnel (matches existing import_bp_batch pattern):
  #
  #   ssh -L 54301:172.19.15.12:54301 a012 -N &
  #   DWAY_DB_PASSWORD=... bin/rails data_migration:dump_excluded_bp[]
  #
  # The CSV is intended to be handed to the curator team. Curator decides
  # per-row whether to recover (e.g. by populating the missing accession
  # in D-way) or to skip permanently.
  desc 'Dump excluded BP submissions to CSV for curator review'
  task :dump_excluded_bp, %i[output_path] => :environment do |_, args|
    output_path = args[:output_path].presence || "tmp/data-migration/excluded-bp-#{Time.current.strftime('%Y%m%d-%H%M%S')}.csv"
    FileUtils.mkdir_p(File.dirname(output_path))

    client = BioProject::StagingClient.new

    begin
      rows = client.enumerate_excluded
    ensure
      client.close
    end

    CSV.open(output_path, 'w') {|csv|
      csv << %w[psub_id reason status_id submitter_id charge_id create_date modified_date]

      rows.each {|r|
        csv << [r.psub_id, r.reason, r.status_id, r.submitter_id, r.charge_id, r.create_date, r.modified_date]
      }
    }

    by_reason = rows.group_by(&:reason).transform_values(&:size).sort_by {|_, n| -n }
    puts "Wrote #{rows.size} excluded row[s] to #{output_path}"
    by_reason.each {|reason, n| puts "  #{reason}: #{n}" }
  end

  # Dump excluded BS submissions — curator-review CSV.
  #
  # "Excluded" means the regular import_bs_batch pipeline would silently
  # drop the row. One reason:
  #   - no_samples: mass.submission row exists but has zero mass.sample
  #                 rows. Importer returns :no_samples.
  #
  # BS submission has no aggregate status_id (status is per-sample), so
  # the CSV columns are slightly different from the BP counterpart.
  # See dump_excluded_bp's comment for production / staging invocation.
  desc 'Dump excluded BS submissions to CSV for curator review'
  task :dump_excluded_bs, %i[output_path] => :environment do |_, args|
    output_path = args[:output_path].presence || "tmp/data-migration/excluded-bs-#{Time.current.strftime('%Y%m%d-%H%M%S')}.csv"
    FileUtils.mkdir_p(File.dirname(output_path))

    client = BioSample::StagingClient.new

    begin
      rows = client.enumerate_excluded
    ensure
      client.close
    end

    CSV.open(output_path, 'w') {|csv|
      csv << %w[ssub_id reason submitter_id organization charge_id create_date modified_date]

      rows.each {|r|
        csv << [r.ssub_id, r.reason, r.submitter_id, r.organization, r.charge_id, r.create_date, r.modified_date]
      }
    }

    puts "Wrote #{rows.size} excluded row[s] to #{output_path}"
    puts '  no_samples: ' + rows.size.to_s if rows.any?
  end
end
