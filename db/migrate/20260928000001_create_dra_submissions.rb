# A DRA submission's curation row, as `projects` is a BioProject's: the one
# thing in it that carries an accession (DRA000072) and a status. What the
# submission holds — its studies, samples, experiments, runs and analyses,
# with their own accessions — is the record's.
#
# The dates are D-way's (`mass.submission`), which it keeps apart from the
# XML: the hold date a curator set, and when the submission went out.
class CreateDRASubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :dra_submissions do |t|
      t.references :submission, null: false, foreign_key: true, index: {unique: true}

      t.string  :accession
      t.integer :status, null: false, default: 5100
      t.date    :hold_date
      t.date    :dist_date
      t.date    :release_date

      t.timestamps

      t.index :accession, unique: true, where: 'accession IS NOT NULL'
      t.index :status
    end
  end
end
