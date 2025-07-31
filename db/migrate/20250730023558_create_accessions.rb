class CreateAccessions < ActiveRecord::Migration[8.0]
  def change
    create_table :accessions do |t|
      t.references :submission, null: false, foreign_key: true

      t.string   :number,          null: false
      t.string   :entry_id,        null: false
      t.integer  :version,         null: false, default: 1
      t.datetime :last_updated_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      t.timestamps

      t.index :number,              unique: true
      t.index %i[entry_id version], unique: true
    end

    create_table :sequences do |t|
      t.string :scope, null: false
      t.bigint :next,  null: false, default: 1

      t.timestamps

      t.index :scope, unique: true
    end
  end
end
