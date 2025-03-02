class AddRawResultToValidations < ActiveRecord::Migration[7.1]
  def change
    add_column :validations, :raw_result, :jsonb
  end
end
