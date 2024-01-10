class RenameKeyToIdOnRequests < ActiveRecord::Migration[7.1]
  def change
    rename_column :objs, :key, :_id
  end
end
