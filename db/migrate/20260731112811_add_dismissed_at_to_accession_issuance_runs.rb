# The result of a bulk press outlives the press. A flash is gone on the
# next click, which is exactly when a curator looks up from the run and
# wonders which of the ten they ticked did nothing — so the summary sits
# on the ledger until it is dismissed, and this is what remembers that.
class AddDismissedAtToAccessionIssuanceRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :accession_issuance_runs, :dismissed_at, :datetime

    # Only ever read as "this curator's most recent undismissed run".
    add_index :accession_issuance_runs, [:actor, :started_at], where: 'dismissed_at IS NULL',
              name: 'index_accession_issuance_runs_undismissed'
  end
end
