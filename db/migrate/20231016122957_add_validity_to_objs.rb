class AddValidityToObjs < ActiveRecord::Migration[7.1]
  def change
    change_table :objs do |t|
      t.string :validity
      t.jsonb  :validation_details

      t.timestamps
    end

    change_table :requests do |t|
      t.remove :result, type: :jsonb
    end
  end
end
