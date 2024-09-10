require_relative '../config/environment'

dir = Rails.root.join('tmp/bioproject_xml')

BioProject::XML.find_each do |xml|
  dir.join("#{xml.submission_id}-#{xml.version.to_s.rjust(3, '0')}.xml").write xml.content
end
