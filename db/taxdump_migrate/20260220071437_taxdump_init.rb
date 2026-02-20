class TaxdumpInit < ActiveRecord::Migration[8.1]
  def change
    create_table :names do |t|
      t.bigint :tax_id,     null: false
      t.string :name_txt,   null: false
      t.string :name_class, null: false

      t.index %i[tax_id name_txt], where: "name_class = 'scientific name'", name: 'index_names_on_tax_id_and_name_txt_scientific'
      t.index %i[tax_id name_txt], where: "name_class = 'common name'",     name: 'index_names_on_tax_id_and_name_txt_common'
      t.index %i[tax_id name_class]
      t.index 'LOWER(name_txt), name_class'
    end

    create_table :nodes do |t|
      t.bigint  :tax_id,        null: false
      t.bigint  :parent_tax_id, null: false
      t.string  :rank,          null: false
      t.boolean :hidden_flag,   null: false
    end
  end
end
