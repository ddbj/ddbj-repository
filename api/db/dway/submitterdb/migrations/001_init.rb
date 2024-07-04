Sequel.migration do
  change do
    create_table :login do
      primary_key :usr_id, type: :bigint

      text      :submitter_id,   null: false
      text      :password,       null: false
      integer   :role,           null: false, default: 0
      boolean   :usable,         null: false, default: true
      boolean   :need_chgpasswd,              default: true
      timestamp :create_date,                 default: Sequel.lit("DATE_TRUNC('second'::text, NOW())")
    end

    create_table :contact do
      text :submitter_id, primary_key: true

      integer :seq_no
      text    :first_name
      text    :middle_name
      text    :last_name
      text    :email
      boolean :is_pi
      boolean :is_contact
    end

    create_table :organization do
      text :submitter_id, primary_key: true

      text :center_name
      text :detail
      text :organization
      text :department
      text :affiliation
      text :phone
      text :phone_ext
      text :fax
      text :url
      text :unit
      text :address
      text :city
      text :state
      text :country
      text :zipcode
    end
  end
end
