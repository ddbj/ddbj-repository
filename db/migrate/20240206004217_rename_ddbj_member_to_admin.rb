class RenameDDBJMemberToAdmin < ActiveRecord::Migration[7.1]
  def change
    rename_column :users, :ddbj_member, :admin
  end
end
