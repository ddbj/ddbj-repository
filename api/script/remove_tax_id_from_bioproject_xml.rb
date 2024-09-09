require_relative '../config/environment'

src  = Rails.root.join('tmp/bioproject_xml')
dest = Rails.root.join('tmp/bioproject_xml_no_tax_id').tap(&:mkpath)

src.glob '*.xml' do |path|
  doc = Nokogiri::XML.parse(path.read)
  doc.at('/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism')&.remove_attribute 'taxID'
  dest.join(path.basename).write doc.to_xml
end
