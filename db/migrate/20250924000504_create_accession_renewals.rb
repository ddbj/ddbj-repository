class CreateAccessionRenewals < ActiveRecord::Migration[8.0]
  def change
    create_table :accession_renewals do |t|
      t.references :accession, null: false, foreign_key: true

      t.string   :progress, null: false, default: "waiting"
      t.string   :validity
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    create_table :accession_renewal_validation_details do |t|
      t.references :renewal, null: false, foreign_key: {to_table: :accession_renewals}

      t.string :severity, null: false
      t.string :message,  null: false

      t.timestamps
    end
  end
end
