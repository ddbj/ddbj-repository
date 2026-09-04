class AddFlatfileOmitsToSubmissions < ActiveRecord::Migration[8.1]
  # The entry ids the flatfile left out when it was written.
  #
  # Written with the file, because it is the only thing that answers
  # "does the file on record match these statuses" in both directions. A
  # timestamp cannot: `entries.updated_at` moves for changes the file has
  # no opinion about — publishing an entry, and the 2026-08-10 locus_date
  # backfill that stamped 9,813,674 rows without touching a file — and
  # does not move for the rules the renderer was compiled with.
  #
  # Null means the file predates this record, which is every file written
  # before this migration. `Submission#flatfile_drift` says so rather than
  # guessing, and the row fills itself in the first time the submission is
  # regenerated.
  def change
    add_column :submissions, :flatfile_omits, :string, array: true

    # The retracted ids of one submission, which is what the comparison
    # reads, and the grouped status count the Entries tab draws. Both were
    # scanning `index_entries_on_submission_id` and going to the heap for
    # the status.
    add_index :entries, %i[submission_id status]
  end
end
