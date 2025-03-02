class AddBasicColumnsToUsers < ActiveRecord::Migration[7.1]
  def change
    change_table :users do |t|
      t.string :email,        null: false
      t.string :first_name,   null: false
      t.string :last_name,    null: false
      t.string :organization, null: false
      t.string :department
      t.string :organization_url
    end
  end
end
