class ChangeValidationsRawResultToJsonb < ActiveRecord::Migration[8.1]
  def change
    change_column :validations, :raw_result, :jsonb, using: 'raw_result::jsonb'
  end
end
