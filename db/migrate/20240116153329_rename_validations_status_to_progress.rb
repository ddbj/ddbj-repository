class RenameValidationsStatusToProgress < ActiveRecord::Migration[7.1]
  def change
    rename_column :validations, :status, :progress
  end
end
