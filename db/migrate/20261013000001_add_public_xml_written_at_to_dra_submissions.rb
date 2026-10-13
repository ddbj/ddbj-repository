class AddPublicXMLWrittenAtToDRASubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :dra_submissions, :public_xml_written_at, :datetime
  end
end
