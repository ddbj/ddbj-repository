require_relative '../config/environment'

dir = Rails.root.join('tmp/bioproject_xml')

BioProject::XML.find_each do |xml|
  dir.join("#{xml.submission_id}-#{xml.version}.xml").write xml.content
end
