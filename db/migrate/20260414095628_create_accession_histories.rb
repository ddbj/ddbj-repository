class CreateAccessionHistories < ActiveRecord::Migration[8.1]
  def change
    create_table :accession_histories do |t|
      t.references :accession, null: false, foreign_key: true
      t.references :user,      null: false, foreign_key: true
      t.string     :action,    null: false

      t.datetime :created_at, null: false
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO accession_histories (accession_id, user_id, action, created_at)
          SELECT a.id, sr.user_id, 'create', a.created_at
          FROM accessions a
          JOIN submissions s ON s.id = a.submission_id
          JOIN submission_requests sr ON sr.submission_id = s.id
        SQL
      end
    end
  end
end
