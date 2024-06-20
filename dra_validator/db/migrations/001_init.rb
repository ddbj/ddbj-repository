Sequel.migration do
  change do
    create_table :submission do
      primary_key :sub_id, type: :bigint

      bigint  :usr_id, null: false
      text    :submitter_id, null: false
      integer :serial, null: false
      integer :charge
      date    :create_date
      date    :submit_date
      date    :hold_date
      date    :dist_date
      date    :finish_date
      text    :note
    end
  end
end
