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

      bigint    :sub_id
      integer   :status
      timestamp :date
    end

    create_table :operation_history do
      primary_key :his_id, type: :bigint

      integer   :type
      text      :summary
      text      :file_name
      timestamp :date
      bigint    :usr_id
      integer   :serial
      text      :submitter_id
    end

    create_table :ext_entity do
      primary_key :ext_id, type: :bigint

      text    :acc_type
      text    :ref_name
      integer :status
    end

    create_table :ext_permit do
      primary_key :per_id, type: :bigint

      bigint :ext_id
      text   :submitter_id
    end
  end
end
