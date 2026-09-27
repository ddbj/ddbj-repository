module DataMigration
  # See SyncJob for the resumption / counter-flush / status state machine.
  # Concurrency is enforced at the call site (admin controller + rake
  # task precheck), NOT via limits_concurrency — see SyncJob class
  # comment for why.
  class SyncDRAJob < SyncJob
    private

    def staging_client_class
      DRA::StagingClient
    end

    def run_importer(sub_id)
      row = @client.fetch(sub_id)
      return :missing if row.nil?

      DRA::Importer.new(row, migration_run_id: @run.uuid).call.outcome
    rescue DRA::Importer::CrossUserError => e
      @run.append_error!("[#{sub_id}] CROSS-USER: #{e.message}")
      :cross_user
    end
  end
end
