class AddViaToValidations < ActiveRecord::Migration[8.0]
  def change
    add_column :validations, :via, :string, null: false
  end
end
