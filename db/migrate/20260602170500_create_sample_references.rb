class CreateSampleReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :sample_references do |t|
      t.references :sample, null: false, foreign_key: true
      t.string :ref_db,        null: false
      t.string :ref_accession, null: false

      t.timestamps
    end

    add_index :sample_references, [:ref_db, :ref_accession]
    add_index :sample_references, [:sample_id, :ref_db, :ref_accession],
      unique: true,
      name:   'index_sample_references_on_sample_db_accession'
  end
end
