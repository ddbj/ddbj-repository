class DRASearchInit < ActiveRecord::Migration[8.0]
  def change
    execute 'CREATE SCHEMA sra'

    create_table 'sra.tax_names', primary_key: %i[tax_id name_class] do |t|
      t.integer :tax_id,   null: false
      t.text    :name_txt, null: false
      t.text    :uniq_name
      t.text    :name_class
      t.date    :date
      t.text    :search_name
    end
  end
end
