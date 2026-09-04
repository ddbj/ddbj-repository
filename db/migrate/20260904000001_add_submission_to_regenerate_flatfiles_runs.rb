class AddSubmissionToRegenerateFlatfilesRuns < ActiveRecord::Migration[8.1]
  # Which submission a run of one submission was about.
  #
  # A run that failed could already be identified — the failure rows
  # carry the reference — and a run that succeeded could not, so the log
  # showed a column of rows all reading "One submission" and the curator
  # who pressed it had no route back to the request they pressed it from.
  #
  # Nullable because most runs are not about one submission: a paste
  # covers whatever the numbers resolve to, and the every-submission run
  # covers the table. `nullify` as on the failure rows — a submission
  # deleted afterwards should not take the record of the run with it.
  def change
    add_reference :regenerate_flatfiles_runs, :submission, foreign_key: {on_delete: :nullify}
  end
end
