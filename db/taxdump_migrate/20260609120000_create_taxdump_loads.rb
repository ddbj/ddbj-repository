class CreateTaxdumpLoads < ActiveRecord::Migration[8.1]
  def change
    create_table :loads do |t|
      t.timestamps
    end
  end
end
