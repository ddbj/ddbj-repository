class RemoveFilenameFromValidationDetails < ActiveRecord::Migration[8.1]
  def change
    remove_column :validation_details, :filename, :string
  end
end
