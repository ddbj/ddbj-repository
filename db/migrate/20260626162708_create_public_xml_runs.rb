class CreatePublicXMLRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :public_xml_runs do |t|
      # 'bioproject' | 'biosample'. Kept as string (not an FK) to mirror
      # MigrationRun's convention.
      t.string :db, null: false

      # 'public'   — the publicly-distributed XML (BP + BS).
      # 'exchange' — Phase B 三極交換用 XML (BP only). Allowed for BP rows;
      #              BS exchange runs are blocked at the model level.
      t.string :kind, null: false

      # 'running' | 'completed' | 'failed'
      t.string :status, null: false, default: 'running'

      # `emitted` is the number of records that landed in the file. For
      # 'public' that's the entire count; for 'exchange' the three delta
      # counters (added/updated/unchanged) sum to the same value and
      # `emitted` stays 0 — the column is reserved for 'public' so the
      # admin doesn't have to special-case the sum.
      t.integer :emitted,   null: false, default: 0
      t.integer :added,     null: false, default: 0
      t.integer :updated,   null: false, default: 0
      t.integer :unchanged, null: false, default: 0

      t.datetime :started_at,  null: false
      t.datetime :finished_at
      t.text     :error_log

      t.timestamps
    end

    add_index :public_xml_runs, %i[db kind status]
    add_index :public_xml_runs, %i[db kind finished_at]
  end
end
