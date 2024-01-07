class AddPurposeToRequests < ActiveRecord::Migration[7.1]
  def change
    add_column :requests, :purpose, :string, null: false
  end
end
