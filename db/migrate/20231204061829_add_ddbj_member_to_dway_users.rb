class AddDDBJMemberToDwayUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :dway_users, :ddbj_member, :boolean, null: false, default: false
  end
end
