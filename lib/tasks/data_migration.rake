require 'csv' # used by dump_excluded_* tasks; csv stopped being a default gem in Ruby 3.4

# Shared scaffolding for the dump_excluded_bp / dump_excluded_bs rake tasks:
# enumerate a StagingClient, write a CSV atomically (tempfile + rename so a
# SIGINT mid-write never leaves a syntactically-complete but truncated file
# for a curator to mistake for a finished dump), and print a per-reason
# breakdown derived from the rows themselves — no hard-coded reason literals
# in the task body, so adding a new reason on either StagingClient surfaces
# in the summary without a parallel rake edit.
module DataMigration
  module DumpExcluded
    module_function

    def call(client_class:, default_stem:, header:, row_mapper:, output_path: nil)
      output_path = output_path.presence ||
                    "tmp/data-migration/#{default_stem}-#{Time.current.strftime('%Y%m%d-%H%M%S')}.csv"
      FileUtils.mkdir_p(File.dirname(output_path))

      client = client_class.new

      rows = begin
        client.enumerate_excluded
      ensure
        client.close
      end

      tmp_path = "#{output_path}.tmp.#{Process.pid}"
      CSV.open(tmp_path, 'w') {|csv|
        csv << header
        rows.each {|r| csv << row_mapper.call(r) }
      }
      File.rename(tmp_path, output_path)

      puts "Wrote #{rows.size} excluded row[s] to #{output_path}"
      rows.group_by(&:reason).transform_values(&:size).sort_by {|_, n| -n }.each {|reason, n|
        puts "  #{reason}: #{n}"
      }
    end
  end
end

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

  # Batch-import every BioProject from D-way staging via
  # `DataMigration::SyncBpJob`. Creates a MigrationRun row so progress
  # / counters / resume state are visible on `/admin/migration_runs`,
  # then runs the job inline (perform_now) — the operator sees live
  # progress through Rails.logger + the job's own checkpoint logging.
  # The admin UI path uses perform_later (queued via SolidQueue,
  # picked up by the in-Puma worker — see SOLID_QUEUE_IN_PUMA).
  #
  # Resume after a crash is automatic via ActiveJob::Continuation —
  # the job persists its cursor per row, so a re-perform picks up
  # where the previous one left off without re-processing already-
  # imported rows. There is no `after` arg anymore.
  #
  # The task refuses to start if a previous run is still :queued or
  # :running. Without that guard, perform_now + an already-running
  # admin-triggered job would race the importer against itself for
  # every row.
  #
  #   ssh -L 54301:172.19.15.12:54301 a012 -N &
  #   DWAY_DB_PASSWORD=... bin/rails data_migration:import_bp_batch
  desc 'Run a BioProject sync (inline). Creates a MigrationRun row + runs DataMigration::SyncBpJob.'
  task import_bp_batch: :environment do
    if (active = MigrationRun.where(db: :bioproject, status: %w[queued running]).order(:id).last)
      abort "Aborting: BP MigrationRun ##{active.id} is already #{active.status}. " \
            'See /admin/migration_runs.'
    end

    run = MigrationRun.create!(db: :bioproject)
    puts "Created MigrationRun ##{run.id} (uuid=#{run.uuid}). Running inline..."

    DataMigration::SyncBpJob.perform_now(run.id)

    run.reload
    puts "Done. status=#{run.status} " + run.counters.map {|k, v| "#{k}=#{v}" }.join(' ')
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

  # Run a BioSample sync inline through DataMigration::SyncBsJob — see
  # import_bp_batch for the wrapping rationale (MigrationRun row,
  # Continuation resume, in-progress precheck).
  #
  #   ssh -L 54301:172.19.15.12:54301 a012 -N &
  #   DWAY_DB_PASSWORD=... bin/rails data_migration:import_bs_batch
  desc 'Run a BioSample sync (inline). Creates a MigrationRun row + runs DataMigration::SyncBsJob.'
  task import_bs_batch: :environment do
    if (active = MigrationRun.where(db: :biosample, status: %w[queued running]).order(:id).last)
      abort "Aborting: BS MigrationRun ##{active.id} is already #{active.status}. " \
            'See /admin/migration_runs.'
    end

    run = MigrationRun.create!(db: :biosample)
    puts "Created MigrationRun ##{run.id} (uuid=#{run.uuid}). Running inline..."

    DataMigration::SyncBsJob.perform_now(run.id)

    run.reload
    puts "Done. status=#{run.status} " + run.counters.map {|k, v| "#{k}=#{v}" }.join(' ')
  end

  # Dump excluded BP submissions — curator-review CSV.
  #
  # "Excluded" means the regular import_bp_batch pipeline would silently
  # drop the row. Three reasons:
  #   - no_project_row: in mass.submission but not in mass.project
  #     (filtered out by the INNER JOIN in `submission_ids`)
  #   - no_accession:   project row present but project_id_prefix +
  #                     project_id_counter is NULL (DB column is the
  #                     sole accession source post-XML-fallback-removal)
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
    DataMigration::DumpExcluded.call(
      client_class: BioProject::StagingClient,
      default_stem: 'excluded-bp',
      header:       %w[psub_id reason status_id submitter_id charge_id create_date modified_date],
      row_mapper:   ->(r) {
        [r.psub_id, r.reason, r.status_id, r.submitter_id, r.charge_id, r.create_date, r.modified_date]
      },
      output_path:  args[:output_path]
    )
  end

  # Dump excluded BS submissions — curator-review CSV.
  #
  # "Excluded" means the regular import_bs_batch pipeline would silently
  # drop the row. One reason today:
  #   - no_samples: mass.submission row exists but has zero mass.sample
  #                 rows. Importer returns :no_samples.
  #
  # BS submission has no aggregate status_id (status is per-sample), so
  # the CSV columns are slightly different from the BP counterpart.
  # See dump_excluded_bp's comment for production / staging invocation.
  desc 'Dump excluded BS submissions to CSV for curator review'
  task :dump_excluded_bs, %i[output_path] => :environment do |_, args|
    DataMigration::DumpExcluded.call(
      client_class: BioSample::StagingClient,
      default_stem: 'excluded-bs',
      header:       %w[ssub_id reason submitter_id organization charge_id create_date modified_date],
      row_mapper:   ->(r) {
        [r.ssub_id, r.reason, r.submitter_id, r.organization, r.charge_id, r.create_date, r.modified_date]
      },
      output_path:  args[:output_path]
    )
  end
end
