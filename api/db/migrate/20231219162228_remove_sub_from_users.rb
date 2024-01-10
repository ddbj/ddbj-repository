class RemoveSubFromUsers < ActiveRecord::Migration[7.1]
  def change
    remove_column :users, :sub, :string, null: false

    add_index :users, :uid, unique: true
  end
end
