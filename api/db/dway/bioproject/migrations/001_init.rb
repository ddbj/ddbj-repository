Sequel.migration do
  change do
    create_table :submission do
      text :submission_id, primary_key: true

      text      :submitter_id
      integer   :status_id,                      default: 100
      timestamp :created_date,      null: false, default: Sequel.function(:now)
      timestamp :modified_date,     null: false, default: Sequel.function(:now)
      integer   :charge_id,         null: false, default: 1
      varchar   :form_status_flags, size: 6,     default: '000000'
    end

    create_table :submission_data do
      primary_key %i[submission_id data_name t_order]

      text      :submission_id, null: false
      text      :data_name,     null: false
      text      :data_value
      integer   :t_order,       null: false, default: -1
      text      :form_name
      timestamp :modified_date, null: false, default: Sequel.function(:now)
    end

    create_table :project do
      text :submission_id, primary_key: true

      text      :project_id_prefix, default: 'PRJDB'
      serial    :project_id_counter
      timestamp :created_date,      null: false, default: Sequel.function(:now)
      timestamp :modified_date,     null: false, default: Sequel.function(:now)
      timestamp :issued_date
      integer   :status_id
      text      :project_type,      null: false
      timestamp :release_date
      timestamp :dist_date
      text      :comment
    end

    create_table :xml do
      primary_key %i[submission_id version]

      text    :submission_id,   null: false
      text    :content,         null: false
      integer :version,         null: false
      text    :registered_date, null: false, default: Sequel.function(:now)
    end
  end
end
