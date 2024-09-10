require_relative '../config/environment'

dir = Rails.root.join('tmp/bioproject_xml')

cond = <<~SQL
  (submission_id, version) IN (
    SELECT submission_id, MAX(version)
    FROM xml
    GROUP BY submission_id
  )
SQL

BioProject::XML.where(cond).find_each do |xml|
  dir.join("#{xml.submission_id}.xml").write xml.content
end
