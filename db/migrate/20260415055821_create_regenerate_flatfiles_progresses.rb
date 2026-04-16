class CreateRegenerateFlatfilesProgresses < ActiveRecord::Migration[8.1]
  def change
    create_table :regenerate_flatfiles_progresses do |t|
      t.integer  :total,     null: false
      t.integer  :processed, null: false, default: 0
      t.datetime :created_at, null: false
    end
  end
end
