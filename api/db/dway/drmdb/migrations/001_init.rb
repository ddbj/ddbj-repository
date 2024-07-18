Sequel.migration do
  change do
    create_table :submission do
      primary_key :sub_id, type: :bigint

      bigint  :usr_id,       null: false
      text    :submitter_id, null: false
      integer :serial,       null: false
      integer :charge
      date    :create_date
      date    :submit_date
      date    :hold_date
      date    :dist_date
      date    :finish_date
      text    :note
    end

    create_table :status_history do
      primary_key :id, type: :bigint

      bigint    :sub_id, null: false
      integer   :status, null: false
      timestamp :date,   null: false, default: Sequel.lit("DATE_TRUNC('second', NOW())")
    end

    create_table :operation_history do
      primary_key :his_id, type: :bigint

      integer   :type,    null: false
      text      :summary, null: false
      text      :file_name
      bytea     :detail
      timestamp :date,    null: false, default: Sequel.lit("DATE_TRUNC('second', NOW())")
      bigint    :usr_id,  null: false
      integer   :serial
      text      :submitter_id
    end

    create_table :ext_entity do
      primary_key :ext_id, type: :bigint

      text    :acc_type, null: false
      text    :ref_name, null: false
      integer :status,   null: false
    end

    create_table :ext_permit do
      primary_key :per_id, type: :bigint

      bigint :ext_id,       null: false
      text   :submitter_id, null: false
    end
  end
end
