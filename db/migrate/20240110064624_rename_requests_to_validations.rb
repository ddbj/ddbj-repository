class RenameRequestsToValidations < ActiveRecord::Migration[7.1]
  def change
    rename_table :requests, :validations

    rename_column :objs,        :request_id, :validation_id
    rename_column :submissions, :request_id, :validation_id

    remove_column :validations, :purpose, :string, null: false
  end
end
