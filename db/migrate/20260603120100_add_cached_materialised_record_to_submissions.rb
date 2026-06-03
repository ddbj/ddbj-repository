class AddCachedMaterialisedRecordToSubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :submissions, :cached_materialised_record, :binary
  end
end
