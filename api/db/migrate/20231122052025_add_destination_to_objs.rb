class AddDestinationToObjs < ActiveRecord::Migration[7.1]
  def change
    add_column :objs, :destination, :string
  end
end
