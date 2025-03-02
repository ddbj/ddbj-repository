class RenameDwayUsersToUsers < ActiveRecord::Migration[7.1]
  def change
    rename_table :dway_users, :users

    rename_column :requests,    :dway_user_id, :user_id
    rename_column :submissions, :dway_user_id, :user_id
  end
end
