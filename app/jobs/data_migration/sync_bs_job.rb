module DataMigration
  # See SyncJob for the resumption / counter-flush / status state machine.
  # Concurrency is enforced at the call site (admin controller + rake
  # task precheck), NOT via limits_concurrency — see SyncJob class
  # comment for why.
  class SyncBsJob < SyncJob
    private

    def staging_client_class
      BioSample::StagingClient
    end

    def run_importer(ssub_id)
      row = @client.fetch(ssub_id)
      return :missing if row.nil?

      BioSample::Importer.new(
        staging_submission: row,
        user_uid:           row.submitter_id || 'migration',
        migration_run_id:   @run.uuid
      ).call.outcome
    rescue BioSample::Importer::CrossUserError => e
      @run.append_error!("[#{ssub_id}] CROSS-USER: #{e.message}")
      :cross_user
    end
  end
end
