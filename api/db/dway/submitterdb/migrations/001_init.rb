Sequel.migration do
  change do
    create_table :login do
      primary_key :usr_id, type: :bigint

      text      :submitter_id,   null: false
      text      :password,       null: false
      integer   :role,           null: false, default: 0
      boolean   :usable,         null: false, default: true
      boolean   :need_chgpasswd,              default: true
      timestamp :create_date,                 default: Sequel.lit("DATE_TRUNC('second', NOW())")
    end

    create_table :contact do
      primary_key :cnt_id, type: :bigint

      text    :submitter_id, null: false
      text    :email
      text    :first_name,                default: ''
      text    :middle_name,               default: ''
      text    :last_name,                 default: ''
      boolean :is_pi,        null: false, default: false
      boolean :is_contact,   null: false, default: false
    end

    create_table :organization do
      text :submitter_id, primary_key: true

      text :detail
      text :center_name
      text :organization
      text :department
      text :affiliation
      text :unit
      text :phone
      text :fax
      text :url
      text :phone_ext
      text :address
      text :city
      text :state
      text :country
      text :zipcode
    end
  end
end
