class AddReadsBuiltAtToDRASubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :dra_submissions, :reads_built_at, :datetime
  end
end
