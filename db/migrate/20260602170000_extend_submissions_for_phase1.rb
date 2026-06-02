class ExtendSubmissionsForPhase1 < ActiveRecord::Migration[8.1]
  def change
    change_table :submissions do |t|
      t.string     :source_id
      t.references :user,              foreign_key: true
      t.string     :converter_version
      t.integer    :canonical_version, null: false, default: 1
      t.uuid       :migration_run_id

      t.index :source_id,        unique: true, where: 'source_id IS NOT NULL'
      t.index :migration_run_id, where: 'migration_run_id IS NOT NULL'
    end
  end
end
