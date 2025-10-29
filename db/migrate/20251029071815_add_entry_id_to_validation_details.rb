class AddEntryIdToValidationDetails < ActiveRecord::Migration[8.1]
  def change
    add_column :validation_details, :entry_id, :string
  end
end
