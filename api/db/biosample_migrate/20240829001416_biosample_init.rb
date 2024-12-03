class BioSampleInit < ActiveRecord::Migration[8.0]
  def change
    execute 'CREATE SCHEMA mass'

    create_table 'mass.attribute', primary_key: %i[smp_id attribute_name] do |t|
      t.integer :seq_no,         null: false
      t.text    :attribute_name, null: false
      t.text    :attribute_value
      t.bigint  :smp_id,         null: false
    end

    create_table 'mass.contact', primary_key: %i[submission_id seq_no] do |t|
      t.text    :submission_id,   null: false
      t.integer :seq_no,          null: false
      t.text    :email
      t.text    :first_name
      t.text    :last_name
      t.timestamp :create_date,   null: false, default: -> { "NOW()" }
      t.timestamp :modified_date, null: false, default: -> { "NOW()" }
    end

    create_table 'mass.contact_form', primary_key: %i[submission_id seq_no] do |t|
      t.text    :submission_id, null: false
      t.integer :seq_no,        null: false
      t.text    :email
      t.text    :first_name
      t.text    :last_name
    end

    create_table 'mass.link', primary_key: %i[smp_id seq_no] do |t|
      t.integer :seq_no, null: false
      t.text    :description
      t.text    :url
      t.bigint  :smp_id, null: false
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

    create_table 'mass.sample', id: false do |t|
      t.bigint :smp_id, primary_key: true

      t.text      :submission_id, null: false
      t.text      :sample_name,  null: false
      t.integer   :release_type
      t.timestamp :release_date
      t.integer   :core_package
      t.integer   :pathogen
      t.integer   :mixs
      t.integer   :env_pkg
      t.integer   :status_id
      t.timestamp :create_date,   null: false, default: -> { "NOW()" }
      t.timestamp :modified_date, null: false, default: -> { "NOW()" }
      t.timestamp :dist_date
      t.text      :package_group
      t.text      :package
      t.text      :env_package
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

    create_table 'mass.xml', primary_key: %i[smp_id version] do |t|
      t.text      :accession_id
      t.integer   :version,       null: false
      t.text      :content,       null: false
      t.timestamp :create_date,   null: false, default: -> { "NOW()" }
      t.timestamp :modified_date, null: false, default: -> { "NOW()" }
      t.bigint    :smp_id,        null: false
    end
  end
end
