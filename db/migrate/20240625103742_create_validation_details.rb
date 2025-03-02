class CreateValidationDetails < ActiveRecord::Migration[7.1]
  def change
    remove_column :objs, :validation_details, :jsonb

    create_table :validation_details do |t|
      t.references :obj, null: false, foreign_key: true

      t.string :code
      t.string :severity
      t.string :message

      t.timestamps
    end
  end
end
