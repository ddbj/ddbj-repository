class AddSourceToMigrationRuns < ActiveRecord::Migration[8.1]
  def change
    # 取り込み元の指紋。既存の run には入らないので、空 = 「記録が無い run」として読む。
    add_column :migration_runs, :source, :jsonb, default: {}, null: false
  end
end
