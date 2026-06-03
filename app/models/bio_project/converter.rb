# frozen_string_literal: true

require 'nokogiri'

module BioProject
  # D-way BioProject XML → DDBJ Record v3 hash.
  #
  # Coverage as of this iteration:
  #   - project: accession, project_type, title, description,
  #     locus_tag_prefix, organism, target (sample_scope / material /
  #     capture / method / data_types), grants, publications, relevance
  #   - submission: submitters (email + first + last + organization)
  #
  # Still deferred (will land in subsequent iterations / Phase 6 ETL):
  #   - project.umbrella_subtype, project.keywords, project.study_types
  #   - umbrella parent/child relations (mass.umbrella_info table)
  #   - Target/Provider, Target/Strain, Target/BiologicalProperties
  #     (Morphology / Environment / Phenotype / RepliconSet)
  #   - Publication: pull full Reference body when present (current
  #     staging mostly has empty Reference with just id + status)
  #   - submission.hold_date from ProjectReleaseDate
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

      organisation_name = node.at_xpath('.//Owner/Organization/Name|.//Description/Organization/Name')&.text&.strip.presence

      submitters = node.xpath('.//Contact').filter_map {|contact|
        person = {
          'email' => contact['email'],
          'first' => contact.at_xpath('./Name/First')&.text,
          'last'  => contact.at_xpath('./Name/Last')&.text
        }.compact.presence

        next nil unless person

        # All contacts under one submission share the Organization in
        # D-way's model — lifting once per contact keeps the v3 record
        # self-describing. Phase 6 needs per-contact org for multi-org
        # submissions.
        person['organization'] = {'name' => organisation_name} if organisation_name
        person
      }

      {'submitters' => submitters}.reject {|_, v| v.blank? }.presence
    end

    def project_block(node)
      return nil unless node

      descr      = node.at_xpath('./ProjectDescr')
      submission = node.at_xpath('./ProjectType/ProjectTypeSubmission')

      {
        'accession'        => node.at_xpath('./ProjectID/ArchiveID/@accession')&.value,
        'project_type'     => @project_row.fetch(:project_type),
        'title'            => descr&.at_xpath('./Title')&.text,
        'description'      => descr&.at_xpath('./Description')&.text,
        'organism'         => organism_block(submission&.at_xpath('./Target/Organism')),
        'locus_tag_prefix' => locus_tag_prefix(descr),
        'grants'           => grants(descr),
        'publications'     => publications(descr),
        'relevance'        => relevance(descr),
        'target'           => target_block(submission)
      }.compact.reject {|_, v| v.respond_to?(:empty?) && v.empty? }
    end

    def locus_tag_prefix(descr)
      return nil unless descr

      descr.xpath('./LocusTagPrefix').filter_map {|n| n.text.presence }.presence
    end

    def organism_block(node)
      return nil unless node

      {
        'taxonomy_id' => node['taxID']&.to_i,
        'name'        => node.at_xpath('./OrganismName')&.text
      }.compact.presence
    end

    def grants(descr)
      return nil unless descr

      descr.xpath('./Grant').filter_map {|g|
        {
          'id'     => g['GrantId']&.presence,
          'title'  => g.at_xpath('./Title')&.text,
          'agency' => g.at_xpath('./Agency')&.text
        }.compact.presence
      }.presence
    end

    # `<Publication id="..." status="..."><Reference /><DbType>ePubmed</DbType></Publication>`.
    # The staging dataset rarely fills the Reference body — most rows
    # only carry the upstream id. We surface id as pubmed_id or doi
    # depending on DbType, keep status as-is, and leave the remaining
    # Publication fields (title / journal / authors) to a later
    # iteration when Reference bodies are populated.
    def publications(descr)
      return nil unless descr

      descr.xpath('./Publication').filter_map {|pub|
        id     = pub['id']&.presence
        status = pub['status']&.presence
        db     = pub.at_xpath('./DbType')&.text

        out = {'status' => status}.compact
        if id
          case db
          when 'eDOI' then out['doi']       = id
          else             out['pubmed_id'] = id # ePubmed or unspecified
          end
        end

        out.presence
      }.presence
    end

    # `<Relevance><Medical>yes</Medical></Relevance>` or
    # `<Relevance><Other /></Relevance>`. Tag names enumerate the
    # relevance categories; flattened to an array of lowercased names
    # for downstream UI / filter use.
    def relevance(descr)
      return nil unless descr

      descr.xpath('./Relevance/*').map {|n| n.name.downcase }.presence
    end

    def target_block(submission)
      return nil unless submission

      target      = submission.at_xpath('./Target')
      method_type = submission.at_xpath('./Method/@method_type')&.value
      data_types  = submission.xpath('./ProjectDataTypeSet/DataType').filter_map {|n| n.text.presence }.presence

      {
        'sample_scope' => target&.[]('sample_scope'),
        'material'     => target&.[]('material'),
        'capture'      => target&.[]('capture'),
        'method'       => method_type,
        'data_types'   => data_types
      }.compact.reject {|_, v| v.respond_to?(:empty?) && v.empty? }.presence
    end
  end
end
