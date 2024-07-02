Sequel.migration do
  change do
    create_table :login do
      primary_key :usr_id, type: :bigint

      text      :submitter_id,   null: false
      text      :password,       null: false
      integer   :role,           null: false, default: 0
      boolean   :usable,         null: false, default: true
      boolean   :need_chgpasswd,              default: true
      timestamp :create_date,                 default: Sequel.lit("date_trunc('second'::text, now())")
    end
  end
end
