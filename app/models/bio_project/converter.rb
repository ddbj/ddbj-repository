# frozen_string_literal: true

require 'nokogiri'

module BioProject
  # D-way BioProject XML → DDBJ Record v3 hash.
  #
  # Coverage as of this iteration:
  #   - project: accession, project_type, title, description,
  #     locus_tag_prefix, organism, target (sample_scope / material /
  #     capture / method / data_types), grants, publications, relevance,
  #     attributes (Strain + BiologicalProperties + Organization +
  #     Reproduction + RepliconSet + GenomeSize + Provider flattened
  #     into the v3 free-form attribute bag)
  #   - submission: submitters (email + first + last + organization
  #     name/role/type lifted from <Organization>), hold_date from
  #     ProjectReleaseDate
  #
  # Still deferred (will land in subsequent iterations / Phase 6 ETL):
  #   - project.umbrella_subtype, project.keywords, project.study_types
  #   - umbrella parent/child relations (mass.umbrella_info table)
  #   - Publication: pull full Reference body when present (current
  #     staging mostly has empty Reference with just id + status)
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

    # Single-valued biology fields under Target/Organism. Mapping is
    # <XPath under Organism node> => v3 attribute name (snake_case).
    # Each entry produces 0..1 attribute (dropped when blank).
    ORGANISM_SCALAR_ATTRS = {
      'Strain'                                       => 'strain',
      'BiologicalProperties/Morphology/Gram'         => 'gram_stain',
      'BiologicalProperties/Morphology/Enveloped'    => 'enveloped',
      'BiologicalProperties/Morphology/Shape'        => 'shape',
      'BiologicalProperties/Morphology/Endospores'   => 'endospores',
      'BiologicalProperties/Morphology/Motility'     => 'motility',
      'BiologicalProperties/Environment/Salinity'    => 'salinity',
      'BiologicalProperties/Environment/OxygenReq'   => 'oxygen_requirement',
      'BiologicalProperties/Environment/OptimumTemperature' => 'optimum_temperature',
      'BiologicalProperties/Environment/TemperatureRange'   => 'temperature_range',
      'BiologicalProperties/Environment/Habitat'     => 'habitat',
      'BiologicalProperties/Phenotype/BioticRelationship'   => 'biotic_relationship',
      'BiologicalProperties/Phenotype/TrophicLevel'  => 'trophic_level',
      'BiologicalProperties/Phenotype/Disease'       => 'disease',
      # `<Organization>` directly under Organism is the eColonial / etc.
      # multicellularity attribute, NOT the submitter Organization.
      # Renamed to `multicellularity` to avoid name collision with
      # submission-side organization data.
      'Organization'                                 => 'multicellularity',
      'Reproduction'                                 => 'reproduction'
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
        'submission'     => submission_block(project_node, submission_node),
        'project'        => project_block(project_node)
      }.compact.reject {|_, v| v.respond_to?(:empty?) && v.empty? }
    end

    private

    def submission_block(project_node, node)
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

      {
        'submitters' => submitters,
        'hold_date'  => hold_date(project_node)
      }.reject {|_, v| v.blank? }.presence
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

    # v3 Submission.hold_date is `str | None`. ProjectReleaseDate ships
    # as ISO-8601 datetime ("2013-05-30T17:44:31.148+09:00"); keep the
    # date part. Anything that doesn't parse drops silently — Phase 6
    # audit will catch outliers.
    def hold_date(project_node)
      return nil unless project_node

      raw = project_node.at_xpath('./ProjectDescr/ProjectReleaseDate')&.text&.strip&.presence
      return nil unless raw

      Date.parse(raw).iso8601
    rescue Date::Error
      nil
    end

    def project_block(node)
      return nil unless node

      descr      = node.at_xpath('./ProjectDescr')
      submission = node.at_xpath('./ProjectType/ProjectTypeSubmission')
      target     = submission&.at_xpath('./Target')

      {
        'accession'        => node.at_xpath('./ProjectID/ArchiveID/@accession')&.value&.presence,
        'project_type'     => @project_row.fetch(:project_type),
        'title'            => descr&.at_xpath('./Title')&.text&.presence,
        'description'      => descr&.at_xpath('./Description')&.text&.presence,
        'organism'         => organism_block(target&.at_xpath('./Organism')),
        'locus_tag_prefix' => locus_tag_prefix(descr),
        'grants'           => grants(descr),
        'publications'     => publications(descr),
        'relevance'        => relevance(descr),
        'target'           => target_block(submission),
        'attributes'       => attributes_block(target)
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

    # Flatten the rich Target/Organism biology block + Target/Provider
    # into v3 project.attributes[] (each Attribute = {name, value,
    # unit?}). v3 has no typed BiologicalProperties slot, so curators
    # query these via the free-form attribute bag.
    def attributes_block(target)
      return nil unless target

      organism = target.at_xpath('./Organism')
      out      = []

      out.concat(organism_scalar_attrs(organism)) if organism
      out.concat(replicon_set_attrs(organism))    if organism
      out.concat(genome_size_attrs(organism))     if organism
      out.concat(provider_attrs(target))

      out.presence
    end

    def organism_scalar_attrs(organism)
      ORGANISM_SCALAR_ATTRS.filter_map {|xpath, name|
        value = organism.at_xpath("./#{xpath}")&.text&.strip&.presence
        next nil unless value

        {'name' => name, 'value' => value}
      }
    end

    # RepliconSet ships any mix of repeating <Replicon> (each with
    # Name/Type/Size sub-elements) plus singleton <Ploidy @type>.
    # Each Replicon leaf becomes one v3 attribute so that the v3 bag
    # preserves N replicons rather than collapsing them. Type is taken
    # as body text (eg "ePlasmid"); @location / @isSingle metadata is
    # dropped at this iteration — surface them via a follow-up if
    # curators need them.
    def replicon_set_attrs(organism)
      rs = organism.at_xpath('./RepliconSet')
      return [] unless rs

      out = []

      rs.xpath('./Replicon').each do |r|
        if (name = r.at_xpath('./Name')&.text&.strip&.presence)
          out << {'name' => 'replicon_name', 'value' => name}
        end
        if (type = r.at_xpath('./Type')&.text&.strip&.presence)
          out << {'name' => 'replicon_type', 'value' => type}
        end
        if (size_node = r.at_xpath('./Size'))
          size = size_node.text&.strip&.presence
          if size
            attr = {'name' => 'replicon_size', 'value' => size}
            if (unit = size_node['units']&.strip&.presence)
              attr['unit'] = unit
            end
            out << attr
          end
        end
      end

      if (ploidy = rs.at_xpath('./Ploidy/@type')&.value&.strip&.presence)
        out << {'name' => 'ploidy', 'value' => ploidy}
      end

      # NOTE: RepliconSet/Count[@repliconType] is intentionally not
      # lifted — v3 Attribute has no slot that fits a typed-count
      # ("1 of type ePlasmid"). Curators get the per-replicon
      # breakdown via replicon_name / replicon_type / replicon_size
      # tuples above; aggregate counts are derivable.

      out
    end

    def genome_size_attrs(organism)
      node  = organism.at_xpath('./GenomeSize')
      return [] unless node

      value = node.text&.strip&.presence
      return [] unless value

      attr = {'name' => 'genome_size', 'value' => value}
      if (unit = node['units']&.strip&.presence)
        attr['unit'] = unit
      end

      [attr]
    end

    def provider_attrs(target)
      value = target.at_xpath('./Provider')&.text&.strip&.presence
      return [] unless value

      [{'name' => 'provider', 'value' => value}]
    end
  end
end
