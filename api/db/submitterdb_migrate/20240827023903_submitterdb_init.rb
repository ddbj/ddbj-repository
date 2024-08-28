class SubmitterDBInit < ActiveRecord::Migration[7.2]
  def change
    create_table :contact, id: false do |t|
      t.bigint    :cnt_id,          primary_key: true
      t.text      :submitter_id,    null: false
      t.text      :email
      t.text      :first_name,                   default: ''
      t.text      :middle_name,                  default: ''
      t.text      :last_name,                    default: ''
      t.boolean   :is_pi,           null: false, default: false
      t.boolean   :is_contact,      null: false, default: false
    end

    create_table :login, id: false do |t|
      t.bigint    :usr_id,          primary_key: true
      t.text      :submitter_id,    null: false
      t.text      :password,        null: false
      t.integer   :role,            null: false, default: 0
      t.boolean   :usable,          null: false, default: true
      t.boolean   :need_chgpasswd,                 default: true
      t.timestamp :create_date,                    default: -> { "DATE_TRUNC('second', NOW())" }
    end

    create_table :organization, id: false do |t|
      t.text :submitter_id, primary_key: true
      t.text :detail
      t.text :center_name
      t.text :organization
      t.text :department
      t.text :affiliation
      t.text :unit
      t.text :phone
      t.text :fax
      t.text :url
      t.text :phone_ext
      t.text :address
      t.text :city
      t.text :state
      t.text :country
      t.text :zipcode
    end
  end
end
