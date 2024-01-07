class AddSubAndApiKeyToDwayUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :dway_users, :sub, :string, null: false
    add_column :dway_users, :api_key, :string, null: false
    add_index :dway_users, :sub, unique: true
    add_index :dway_users, :api_key, unique: true

    remove_index :dway_users, :uid, unique: true
  end
end
