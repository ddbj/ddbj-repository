# frozen_string_literal: true

require 'nokogiri'

module BioProject
  # D-way BioProject XML → DDBJ Record v3 hash. Phase 3 spike scope: enough
  # fields to drive the admin show page (accession / project_type / title /
  # description / organism / locus_tag / submitters). Full field coverage is
  # tracked in Phase 4 of tmp/data-migration/implementation-plan.md.
  class Converter
    SOURCE_FORMAT = 'dway_bp_xml'

    def initialize(xml:, project_row:)
      @xml         = xml
      @project_row = project_row
    end

    def call
      doc = Nokogiri::XML(@xml)
      doc.remove_namespaces!

      project_node    = doc.at_xpath('//Project/Project')
      submission_node = doc.at_xpath('//Submission/Submission')

      {
        'schema_version' => 'v3',
        'provenance'     => {'source_format' => SOURCE_FORMAT},
        'submission'     => submission_block(submission_node),
        'project'        => project_block(project_node)
      }.compact.reject {|_, v| v.respond_to?(:empty?) && v.empty? }
    end

    private

    def submission_block(node)
      return nil unless node

      submitters = node.xpath('.//Contact').filter_map {|contact|
        {
          'email' => contact['email'],
          'first' => contact.at_xpath('./Name/First')&.text,
          'last'  => contact.at_xpath('./Name/Last')&.text
        }.compact.presence
      }

      {'submitters' => submitters}.reject {|_, v| v.blank? }.presence
    end

    def project_block(node)
      return nil unless node

      organism_node = node.at_xpath('.//Target/Organism')
      locus_tag     = node.at_xpath('.//ProjectDescr/LocusTagPrefix')&.text

      {
        'accession'        => node.at_xpath('.//ProjectID/ArchiveID/@accession')&.value,
        'project_type'     => @project_row.fetch(:project_type),
        'title'            => node.at_xpath('.//ProjectDescr/Title')&.text,
        'description'      => node.at_xpath('.//ProjectDescr/Description')&.text,
        'organism'         => organism_block(organism_node),
        'locus_tag_prefix' => locus_tag.present? ? [locus_tag] : nil
      }.compact
    end

    def organism_block(node)
      return nil unless node

      {
        'taxonomy_id' => node['taxID']&.to_i,
        'name'        => node.at_xpath('./OrganismName')&.text
      }.compact.presence
    end
  end
end
