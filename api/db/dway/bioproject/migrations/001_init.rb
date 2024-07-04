Sequel.migration do
  change do
    create_table :submission do
      text :submission_id, primary_key: true

      text    :submitter_id
      integer :status_id
      text    :created_date
      text    :modified_date
      integer :charge_id
      text    :form_status_flags
    end

    create_table :submission_data do
      primary_key :id

      text    :submission_id
      text    :data_name
      text    :data_value
      integer :t_order
      text    :form_name
      text    :modified_date
    end

    create_table :project do
      text :submission_id, primary_key: true

      text    :project_id_prefix
      integer :project_id_counter
      text    :created_date
      text    :modified_date
      text    :release_date
      text    :issued_date
      text    :dist_date
      integer :status_id
      text    :project_type
      text    :comment
    end

    create_table :xml do
      primary_key :id, type: :bigint

      text    :submission_id
      text    :content
      integer :version
      text    :registered_date
    end
  end
end
