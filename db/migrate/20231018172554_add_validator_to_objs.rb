class AddValidatorToObjs < ActiveRecord::Migration[7.1]
  def change
    add_column :objs, :validator, :string
  end
end
