class AddMigrationRunIdToSubmissionRequests < ActiveRecord::Migration[8.1]
  # Migration-sourced BP/BS submissions never went through the
  # interactive upload flow, so they have no SubmissionRequest. To keep
  # the request the single unit everywhere (list + detail, for both
  # submitters and curators), the importer now creates a synthetic
  # request per submission. `migration_run_id` marks those synthetic
  # rows so the model can waive the `ddbj_record` attachment rule that
  # only the interactive flow satisfies. Mirrors the partial index on
  # `submissions.migration_run_id`.
  def change
    add_column :submission_requests, :migration_run_id, :uuid
    add_index  :submission_requests, :migration_run_id, where: 'migration_run_id IS NOT NULL'
  end
end
