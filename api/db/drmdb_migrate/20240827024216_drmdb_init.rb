class DRMDBInit < ActiveRecord::Migration[8.0]
  def change
    execute 'CREATE SCHEMA mass'

    create_table 'mass.accession_entity', id: false do |t|
      t.bigint :acc_id, primary_key: true

      t.text    :alias,     null: false
      t.text    :center_name
      t.text    :acc_type,  null: false
      t.integer :acc_no
      t.boolean :is_delete, null: false, default: false
    end

    create_table 'mass.accession_relation', id: false do |t|
      t.bigint :rel_id, primary_key: true

      t.bigint :grp_id, null: false
      t.bigint :acc_id, null: false
      t.bigint :p_acc_id
    end

    create_table 'mass.batch', id: false do |t|
      t.bigint :bat_id, primary_key: true

      t.integer   :status,       null: false
      t.timestamp :updated,      null: false, default: -> { "DATE_TRUNC('second', NOW())" }
      t.bigint    :main_meta_id, null: false
      t.bigint    :sub_meta_id,  null: false
      t.bigint    :usr_id,       null: false
      t.integer   :serial,       null: false
      t.text      :machine
      t.integer   :priority,     null: false, default: 50
    end

    create_table 'mass.ext_entity', id: false do |t|
      t.bigint :ext_id, primary_key: true

      t.text   :acc_type, null: false
      t.text   :ref_name, null: false
      t.integer :status,  null: false
    end

    create_table 'mass.ext_permit', id: false do |t|
      t.bigint :per_id, primary_key: true

      t.bigint :ext_id,       null: false
      t.text   :submitter_id, null: false
    end

    create_table 'mass.ext_relation', id: false do |t|
      t.bigint :rel_id, primary_key: true

      t.bigint :grp_id, null: false
      t.bigint :acc_id
      t.bigint :ext_id, null: false
    end

    create_table 'mass.meta_entity', id: false do |t|
      t.bigint    :meta_id, primary_key: true

      t.bigint    :acc_id,       null: false
      t.integer   :meta_version, null: false
      t.text      :type,         null: false
      t.text      :content,      null: false
      t.timestamp :date,         null: false, default: -> { "DATE_TRUNC('second', NOW())" }
    end

    create_table 'mass.operation_history', id: false do |t|
      t.bigint :his_id, primary_key: true

      t.integer   :type,    null: false
      t.text      :summary, null: false
      t.text      :file_name
      t.binary    :detail
      t.timestamp :date,    null: false, default: -> { "DATE_TRUNC('second', NOW())" }
      t.bigint    :usr_id,  null: false
      t.integer   :serial
      t.text      :submitter_id
    end

    create_table 'mass.status_history' do |t|
      t.bigint    :sub_id, null: false
      t.integer   :status, null: false
      t.timestamp :date,   null: false, default: -> { "DATE_TRUNC('second', NOW())" }
    end

    create_table 'mass.submission', id: false do |t|
      t.bigint :sub_id, primary_key: true

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

    create_table 'mass.submission_component', id: false do |t|
      t.bigint :det_id, primary_key: true

      t.bigint :grp_id,      null: false
      t.text   :field_key,   null: false
      t.text   :field_value, null: false
    end

    create_table 'mass.submission_group', id: false do |t|
      t.bigint :grp_id, primary_key: true

      t.bigint    :sub_id,         null: false
      t.integer   :submit_version, null: false
      t.timestamp :date,           null: false, default: -> { "DATE_TRUNC('second', NOW())" }
      t.boolean   :valid,          null: false
      t.integer   :serial_version
    end
  end
end
