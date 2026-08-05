class IndexCurationRowsAwaitingAccession < ActiveRecord::Migration[8.1]
  # The "Awaiting accession" bucket is two correlated EXISTS subqueries
  # (`submission_id = ? AND accession IS NULL AND status IN (...)`), and it
  # runs on every admin page render because the nav badge counts it.
  #
  # Both tables already index `submission_id` and `status` separately, so
  # PostgreSQL had to probe one and filter the other for every request row.
  # A partial composite matching the predicate keeps the badge to an index
  # scan over only the rows that can possibly qualify — which, once a
  # corpus is mostly accessioned, is a small fraction of it.
  def change
    add_index :projects, [:submission_id, :status],
              where: 'accession IS NULL',
              name:  'index_projects_awaiting_accession'

    add_index :samples, [:submission_id, :status],
              where: 'accession IS NULL',
              name:  'index_samples_awaiting_accession'
  end
end
