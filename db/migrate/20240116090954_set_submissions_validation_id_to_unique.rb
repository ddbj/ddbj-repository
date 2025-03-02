class SetSubmissionsValidationIdToUnique < ActiveRecord::Migration[7.1]
  def change
    remove_index :submissions, :validation_id
    add_index    :submissions, :validation_id, unique: true
  end
end
