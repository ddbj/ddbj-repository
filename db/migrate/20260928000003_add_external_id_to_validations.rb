# The run a check is carried out as elsewhere: ddbj-validator's uuid for a
# BioProject or BioSample record, which the check polls until it finishes,
# and how many times the record has been sent — a validator that loses its
# runs is sent the record again only a few times. Nil / 0 for a check the
# repository makes itself (ST.26).
class AddExternalIdToValidations < ActiveRecord::Migration[8.1]
  def change
    change_table :validations, bulk: true do |t|
      t.string  :external_id
      t.integer :external_sends, null: false, default: 0
    end
  end
end
