class CreateDwayTakeovers < ActiveRecord::Migration[8.1]
  def change
    create_table :dway_takeovers do |t|
      t.datetime :taken_over_at, null: false
      t.string   :taken_over_by, null: false

      # One: D-way is handed over once, all of it.
      t.boolean :singleton, null: false, default: true
      t.index   :singleton, unique: true

      t.check_constraint 'singleton', name: 'dway_takeovers_singleton'
    end
  end
end
