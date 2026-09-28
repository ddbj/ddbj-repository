# The run a check is carried out as elsewhere: ddbj-validator's uuid for a
# BioProject or BioSample record, which the check polls until it finishes.
# Nil for a check the repository makes itself (ST.26).
class AddExternalIdToValidations < ActiveRecord::Migration[8.1]
  def change
    add_column :validations, :external_id, :string
  end
end
