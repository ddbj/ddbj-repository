class AddNotesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :notes, :text, null: false, default: ''
  end
end
