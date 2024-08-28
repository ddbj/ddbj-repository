class DRMDBInit < ActiveRecord::Migration[7.2]
  def change
    create_table :ext_entity, id: false do |t|
      t.bigint :ext_id,  primary_key: true
      t.text   :acc_type, null: false
      t.text   :ref_name, null: false
      t.integer :status,  null: false
    end

    create_table :ext_permit, id: false do |t|
      t.bigint :per_id,       primary_key: true
      t.bigint :ext_id,       null: false
      t.text   :submitter_id, null: false
    end

    create_table :operation_history, id: false do |t|
      t.bigint    :his_id,  primary_key: true
      t.integer   :type,    null: false
      t.text      :summary, null: false
      t.text      :file_name
      t.binary    :detail
      t.timestamp :date,    null: false, default: -> { "DATE_TRUNC('second', NOW())" }
      t.bigint    :usr_id,  null: false
      t.integer   :serial
      t.text      :submitter_id
    end

    create_table :status_history do |t|
      t.bigint    :sub_id, null: false
      t.integer   :status, null: false
      t.timestamp :date,   null: false, default: -> { "DATE_TRUNC('second', NOW())" }
    end

    create_table :submission, id: false do |t|
      t.bigint  :sub_id,       primary_key: true
      t.bigint  :usr_id,       null: false
      t.text    :submitter_id, null: false
      t.integer :serial,       null: false
      t.integer :charge
      t.date    :create_date
      t.date    :submit_date
      t.date    :hold_date
      t.date    :dist_date
      t.date    :finish_date
      t.text    :note
    end
  end
end
