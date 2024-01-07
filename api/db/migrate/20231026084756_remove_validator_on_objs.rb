class RemoveValidatorOnObjs < ActiveRecord::Migration[7.1]
  def change
    remove_column :objs, :validator
  end
end
