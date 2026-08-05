# One press of Issue, however many submissions it covered.
#
# Issuance is one transaction per submission, so a run genuinely can
# report "2 of 3 done" — unlike a TSV import, where the write is
# indivisible. That makes the run the unit a curator watches, and the
# place the outcome stays: what was allocated, what was skipped and why,
# and when each submitter was mailed.
#
# `origin` records where it was started from ("All requests (3
# submissions)"), because a support question a week later begins with
# "somebody issued these" and the answer starts with who and from where.
class CreateAccessionIssuanceRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :accession_issuance_runs do |t|
      t.string   :actor,      null: false
      t.string   :origin,     null: false
      t.datetime :started_at, null: false

      t.timestamps
    end

    add_reference :accession_issuances, :run, foreign_key: {to_table: :accession_issuance_runs}
  end
end
