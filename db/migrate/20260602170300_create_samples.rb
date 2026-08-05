class CreateSamples < ActiveRecord::Migration[8.1]
  def change
    create_table :samples do |t|
      t.references :submission,    null: false, foreign_key: true
      t.string     :accession
      t.string     :sample_name,   null: false
      t.integer    :status,        null: false, default: 5100
      t.string     :title
      t.string     :package_group
      t.string     :package
      t.string     :env_package
      t.integer    :taxonomy_id
      t.string     :organism
      t.integer    :release_type
      t.date       :release_date
      t.date       :dist_date
      t.references :assignee,      foreign_key: {to_table: :users}

      t.timestamps
    end

    add_index :samples, :accession, unique: true, where: 'accession IS NOT NULL'
    add_index :samples, :sample_name
    add_index :samples, :status
    add_index :samples, :package_group
    add_index :samples, :package
  end
end
