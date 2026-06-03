module DataMigration
  # See SyncJob for the resumption / counter-flush / status state machine.
  # Concurrency is enforced at the call site (admin controller + rake
  # task precheck), NOT via limits_concurrency — see SyncJob class
  # comment for why.
  class SyncBpJob < SyncJob
    private

    def staging_client_class
      BioProject::StagingClient
    end

    def run_importer(psub_id)
      row = @client.fetch(psub_id)
      return :no_xml if row.nil? || row.xml.blank?

      BioProject::Importer.new(
        psub_id:          row.psub_id,
        xml:              row.xml,
        user_uid:         row.submitter_id || 'migration',
        project_type:     row.project_type,
        accession:        row.accession,
        status:           row.status_id,
        migration_run_id: @run.uuid
      ).call.outcome
    rescue BioProject::Importer::CrossUserError => e
      @run.append_error!("[#{psub_id}] CROSS-USER: #{e.message}")
      :cross_user
    end
  end
end
