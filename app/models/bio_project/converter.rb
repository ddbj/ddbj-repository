# frozen_string_literal: true

require 'nokogiri'

module BioProject
  # D-way BioProject XML → DDBJ Record v3 hash.
  #
  # Coverage as of this iteration:
  #   - project: accession, project_type, title, description,
  #     locus_tag_prefix, organism, target (sample_scope / material /
  #     capture / method / data_types), grants, publications, relevance
  #   - submission: submitters (email + first + last + organization
  #     name/role/type lifted from <Organization>)
  #
  # Still deferred (will land in subsequent iterations / Phase 6 ETL):
  #   - project.umbrella_subtype, project.keywords, project.study_types
  #   - umbrella parent/child relations (mass.umbrella_info table)
  #   - Target/Provider, Target/Strain, Target/BiologicalProperties
  #     (Morphology / Environment / Phenotype / RepliconSet)
  #   - Publication: pull full Reference body when present (current
  #     staging mostly has empty Reference with just id + status)
  #   - submission.hold_date from ProjectReleaseDate
  #   - Grant agency abbreviation (v3 Grant schema is just id/title/
  #     agency; the <Agency @abbr> attribute has no slot. Accepting the
  #     loss; spec change would be needed to surface "JSPC" etc.)
  class Converter
    SOURCE_FORMAT = 'dway_bp_xml'

    # `case` whitelist for <Publication><DbType>; everything outside
    # this map (typo, missing element, unrecognised provider) drops the
    # publication's id rather than silently mis-binding e.g. an
    # eBookChapter ISBN to pubmed_id.
    PUBLICATION_DB_FIELDS = {
      'ePubmed' => 'pubmed_id',
      'eDOI'    => 'doi'
    }.freeze

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

      org_block = submission_organization(node)

      submitters = node.xpath('.//Contact').filter_map {|contact|
        person = {
          'email' => contact['email']&.strip&.presence,
          'first' => contact.at_xpath('./Name/First')&.text&.strip&.presence,
          'last'  => contact.at_xpath('./Name/Last')&.text&.strip&.presence
        }.compact.presence

        next nil unless person

        # All contacts under one submission share the Organization in
        # D-way's model — lifting once per contact keeps the v3 record
        # self-describing. Phase 6 needs per-contact org for multi-org
        # submissions.
        person['organization'] = org_block if org_block
        person
      }

      {'submitters' => submitters}.reject {|_, v| v.blank? }.presence
    end

    def submission_organization(node)
      org = node.at_xpath('.//Owner/Organization|.//Description/Organization')
      return nil unless org

      {
        'name' => org.at_xpath('./Name')&.text&.strip&.presence,
        'role' => org['role']&.strip&.presence,
        'type' => org['type']&.strip&.presence,
        'url'  => org['url']&.strip&.presence
      }.compact.presence
    end

    def project_block(node)
      return nil unless node

      descr      = node.at_xpath('./ProjectDescr')
      submission = node.at_xpath('./ProjectType/ProjectTypeSubmission')

      {
        'accession'        => node.at_xpath('./ProjectID/ArchiveID/@accession')&.value&.presence,
        'project_type'     => @project_row.fetch(:project_type),
        'title'            => descr&.at_xpath('./Title')&.text&.presence,
        'description'      => descr&.at_xpath('./Description')&.text&.presence,
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

      # `Integer(_, exception: false)` rejects non-numeric taxIDs
      # ('unknown', 'sp.', '') by returning nil — bare `to_i` would
      # silently coerce them to 0 and persist a non-existent NCBI
      # taxonomy id. Mirrors BioSample::Converter#organism_block.
      {
        'taxonomy_id' => Integer(node['taxID'].to_s, 10, exception: false),
        'name'        => node.at_xpath('./OrganismName')&.text&.strip&.presence
      }.compact.presence
    end

    def grants(descr)
      return nil unless descr

      descr.xpath('./Grant').filter_map {|g|
        {
          'id'     => g['GrantId']&.strip&.presence,
          'title'  => g.at_xpath('./Title')&.text&.strip&.presence,
          'agency' => g.at_xpath('./Agency')&.text&.strip&.presence
        }.compact.presence
      }.presence
    end

    # `<Publication id="..." status="..."><Reference /><DbType>ePubmed</DbType></Publication>`
    # OR `<Publication id="..."><Reference><DbType>eDOI</DbType></Reference></Publication>`
    # (D-way ships both shapes). `.//DbType` matches either depth.
    # Unknown DbTypes drop the id rather than silently mis-bind it to
    # pubmed_id; status survives so the curator sees the publication
    # existed even when its id couldn't be slotted.
    def publications(descr)
      return nil unless descr

      descr.xpath('./Publication').filter_map {|pub|
        id        = pub['id']&.strip&.presence
        status    = pub['status']&.strip&.presence
        db        = pub.at_xpath('.//DbType')&.text&.strip
        field     = PUBLICATION_DB_FIELDS[db]

        out = {'status' => status}.compact
        out[field] = id if id && field

        out.presence
      }.presence
    end

    # v3 spec: `relevance: dict[str, str]`. Each `<Relevance>` child
    # element name keys an entry whose value is the element's body text
    # (the curator-entered description, especially relevant for
    # `<Other>free text</Other>`). Empty bodies collapse to the empty
    # string rather than being dropped, because the *presence* of the
    # category is itself the signal — losing it would conflate "Medical
    # but no description" with "not Medical at all".
    def relevance(descr)
      return nil unless descr

      descr.xpath('./Relevance/*').to_h {|n| [n.name.downcase, n.text.to_s.strip] }.presence
    end

    def target_block(submission)
      return nil unless submission

      target      = submission.at_xpath('./Target')
      method_type = submission.at_xpath('./Method/@method_type')&.value&.presence
      data_types  = submission.xpath('./ProjectDataTypeSet/DataType').filter_map {|n| n.text&.strip&.presence }.presence

      {
        'sample_scope' => target&.[]('sample_scope')&.strip&.presence,
        'material'     => target&.[]('material')&.strip&.presence,
        'capture'      => target&.[]('capture')&.strip&.presence,
        'method'       => method_type,
        'data_types'   => data_types
      }.compact.reject {|_, v| v.respond_to?(:empty?) && v.empty? }.presence
    end
  end
end
