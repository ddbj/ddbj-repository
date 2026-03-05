class AddIndexesToTaxdumpNodes < ActiveRecord::Migration[8.1]
  def change
    add_index :nodes, :tax_id
    add_index :nodes, :parent_tax_id
  end
end
