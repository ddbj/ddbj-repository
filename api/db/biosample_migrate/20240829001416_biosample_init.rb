class BioSampleInit < ActiveRecord::Migration[7.2]
  def change
    execute 'CREATE SCHEMA mass'

    create_table 'mass.contact_form', primary_key: %i[submission_id seq_no] do |t|
      t.text    :submission_id, null: false
      t.integer :seq_no,        null: false
      t.text    :email
      t.text    :first_name
      t.text    :last_name
    end

    create_table 'mass.link_form', primary_key: %i[submission_id seq_no] do |t|
      t.text    :submission_id, null: false
      t.integer :seq_no,        null: false
      t.text    :description
      t.text    :url
    end

    create_table 'mass.operation_history', id: false do |t|
      t.bigint :his_id, primary_key: true

      t.integer   :type
      t.text      :summary
      t.text      :file_name
      t.binary    :detail
      t.timestamp :date
      t.bigint    :usr_id
      t.integer   :serial
      t.text      :submitter_id
      t.text      :submission_id
    end

    create_table 'mass.submission', id: false do |t|
      t.text :submission_id, primary_key: true

      t.text      :submitter_id
      t.text      :organization
      t.text      :organization_url
      t.text      :comment
      t.integer   :charge_id,     default: 1
      t.timestamp :create_date,   null: false, default: -> { "NOW()" }
      t.timestamp :modified_date, null: false, default: -> { "NOW()" }
    end

    create_table 'mass.submission_form', id: false do |t|
      t.text :submission_id, primary_key: true

      t.text      :submitter_id,  null: false
      t.integer   :status_id,     null: false
      t.text      :organization
      t.text      :organization_url
      t.integer   :release_type
      t.integer   :core_package
      t.integer   :pathogen
      t.integer   :mixs
      t.integer   :env_pkg
      t.text      :attribute_file_name
      t.text      :attribute_file
      t.text      :comment
      t.timestamp :create_date,   null: false, default: -> { "NOW()" }
      t.timestamp :modified_date, null: false, default: -> { "NOW()" }
      t.text      :package_group
      t.text      :package
      t.text      :env_package
    end
  end
end
