require_relative '../config/environment'

src  = Rails.root.join('tmp/bioproject_xml')
dest = Rails.root.join('tmp/bioproject_xml_cleaned').tap(&:mkpath)

src.glob '*.xml' do |path|
  doc = Nokogiri::XML.parse(path.read)

  if archive_id = doc.at('/PackageSet/Package/Project/Project/ProjectID/ArchiveID')
    archive_id[:accession] ||= 'PRJDB0000'
    archive_id[:archive]   ||= 'DDBJ'
  end

  doc.at('/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism')&.remove_attribute 'taxID'
  doc.at('/PackageSet/Package/Project/Project/ProjectDescr/ProjectReleaseDate')&.remove

  dest.join(path.basename).write doc.to_xml
end
