class BioProjectInit < ActiveRecord::Migration[7.2]
  def change
    execute 'CREATE SCHEMA mass'

    create_table 'mass.project', id: false do |t|
      t.text      :submission_id,     primary_key: true
      t.text      :project_id_prefix, default: 'PRJDB'
      t.serial    :project_id_counter
      t.timestamp :created_date,      null: false, default: -> { 'NOW()' }
      t.timestamp :modified_date,     null: false, default: -> { 'NOW()' }
      t.timestamp :issued_date
      t.integer   :status_id
      t.text      :project_type,      null: false
      t.timestamp :release_date
      t.timestamp :dist_date
      t.text      :comment
    end

    create_table 'mass.submission', id: false do |t|
      t.text      :submission_id,     primary_key: true
      t.text      :submitter_id
      t.integer   :status_id,         default: 100
      t.timestamp :created_date,      null: false, default: -> { 'NOW()' }
      t.timestamp :modified_date,     null: false, default: -> { 'NOW()' }
      t.integer   :charge_id,         null: false, default: 1
      t.string    :form_status_flags, limit: 6,    default: '000000'
    end

    create_table 'mass.submission_data', primary_key: %i[submission_id data_name t_order] do |t|
      t.text      :submission_id, null: false
      t.text      :data_name,     null: false
      t.text      :data_value
      t.integer   :t_order,       null: false, default: -1
      t.text      :form_name
      t.timestamp :modified_date, null: false, default: -> { 'NOW()' }
    end

    create_table 'mass.xml', primary_key: %i[submission_id version] do |t|
      t.text    :submission_id,   null: false
      t.text    :content,         null: false
      t.integer :version,         null: false
      t.text    :registered_date, null: false, default: -> { 'NOW()' }
    end
  end
end
