class AddFinishedAtToValidations < ActiveRecord::Migration[7.1]
  def change
    add_column :validations, :finished_at, :datetime
  end
end
