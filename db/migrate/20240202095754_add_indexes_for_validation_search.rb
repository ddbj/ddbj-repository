class AddIndexesForValidationSearch < ActiveRecord::Migration[7.1]
  def change
    add_index :validations, :db
    add_index :validations, :created_at
    add_index :validations, :progress

    add_index :objs, :validity
  end
end
