class AddViaToValidations < ActiveRecord::Migration[8.0]
  def change
    add_column :validations, :via, :string

    execute <<~SQL
      UPDATE validations SET via = 'file';
    SQL

    change_column_null :validations, :via, false
  end
end
