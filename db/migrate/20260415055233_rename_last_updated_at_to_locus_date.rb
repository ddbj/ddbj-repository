class RenameLastUpdatedAtToLocusDate < ActiveRecord::Migration[8.1]
  def change
    rename_column :accessions, :last_updated_at, :locus_date
    change_column :accessions, :locus_date, :date, null: false
  end
end
