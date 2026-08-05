class CreateMigrationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :migration_runs do |t|
      t.string  :db,     null: false # bioproject / biosample
      t.string  :status, null: false, default: 'queued'

      # Stamped on Submission.migration_run_id so admin can pivot from a run
      # back to the rows it touched (Submission.where(migration_run_id: uuid)).
      t.uuid :uuid, null: false

      t.integer :total
      t.jsonb   :counters,  null: false, default: {}
      t.text    :error_log

      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :migration_runs, :uuid, unique: true
    add_index :migration_runs, %i[db status]
    add_index :migration_runs, :created_at
  end
end
