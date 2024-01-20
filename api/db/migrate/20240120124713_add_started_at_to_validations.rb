class AddStartedAtToValidations < ActiveRecord::Migration[7.1]
  def change
    add_column :validations, :started_at, :datetime
  end
end
