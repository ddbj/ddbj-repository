class RemoveColumnsOnUsers < ActiveRecord::Migration[7.2]
  def change
    remove_column :users, :email,            :string, null: false
    remove_column :users, :first_name,       :string, null: false
    remove_column :users, :last_name,        :string, null: false
    remove_column :users, :organization,     :string, null: false
    remove_column :users, :department,       :string
    remove_column :users, :organization_url, :string
  end
end
