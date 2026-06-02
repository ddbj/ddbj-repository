class ExtendSubmissionsForPhase1 < ActiveRecord::Migration[8.1]
  def up
    change_table :submissions do |t|
      t.string     :source_id
      t.references :user,              foreign_key: true
      t.string     :converter_version
      t.integer    :canonical_version, null: false, default: 1
      t.uuid       :migration_run_id

      t.index :source_id,        unique: true, where: 'source_id IS NOT NULL'
      t.index :migration_run_id, where: 'migration_run_id IS NOT NULL'
    end

    # Backfill owner from the existing submission_requests path so that the
    # new direct Submission#user association returns the same records as the
    # legacy `has_many :submissions, through: :submission_requests`.
    execute <<~SQL.squish
      UPDATE submissions
         SET user_id = submission_requests.user_id
        FROM submission_requests
       WHERE submission_requests.submission_id = submissions.id
         AND submissions.user_id IS NULL
    SQL

    # Production has 0 orphans (verified 2026-06-02); staging orphans must be
    # cleaned manually before deploy. If any remain we'd rather fail loudly
    # than silently store ownerless records.
    n = ActiveRecord::Base.connection.select_value(
      'SELECT COUNT(*) FROM submissions WHERE user_id IS NULL'
    ).to_i

    if n.positive?
      raise "Refusing to add NOT NULL constraint while #{n} submission(s) lack a user_id. " \
            'Backfill manually or delete the orphans before re-running this migration.'
    end

    change_column_null :submissions, :user_id, false
  end

  def down
    change_column_null :submissions, :user_id, true

    change_table :submissions do |t|
      t.remove_index :migration_run_id
      t.remove_index :source_id

      t.remove :migration_run_id
      t.remove :canonical_version
      t.remove :converter_version
      t.remove_references :user, foreign_key: true
      t.remove :source_id
    end
  end
end
