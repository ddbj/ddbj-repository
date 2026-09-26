# frozen_string_literal: true

require 'nokogiri'

module PublicXML
  module Bp
    # Render a single <Package> element from a v3 DDBJ Record hash.
    #
    # Reverse of BioProject::Converter. Aimed at structural equivalence
    # with the legacy bpbatch output (not byte-for-byte): the consumer
    # parser at NCBI/EBI relies on element/attribute identity, so we
    # reconstitute the same nesting and the same attribute names —
    # including the attribute-bag biology block that the forward
    # Converter flattened into project.attributes[].
    #
    # The encoding (UTF-8 vs ISO-8859-1) is decided at the file level by
    # the Exporter, not here — Nokogiri serialises a Builder fragment
    # without an XML declaration.
    class PackageRenderer
      # Forward map shared with BioProject::Converter — keys are the
      # XPath (relative to Organism) and values are the v3 attribute
      # name. We use it in the reverse direction here: element xpath →
      # look up the attribute name → fetch its value from the bag.
      ORGANISM_SCALAR_ATTRS = BioProject::Converter::ORGANISM_SCALAR_ATTRS

      # The Objectives/Data@data_type vocabulary (the XSD's enumeration).
      OBJECTIVE_DATA_TYPES = %w[
        eRawSequenceReads eSequence eAnalysis eAssembly eAnnotation eVariation
        eEpigeneticMarkers eExpression eMaps ePhenotype eOther
      ].to_set.freeze

      # The element names under <Relevance>, which the Converter lowercases.
      RELEVANCE_ELEMENTS = %w[Agricultural Medical Industrial Environmental Evolution ModelOrganism Other].index_by(&:downcase).freeze
      REPLICON_INDEX_RE     = /\Areplicon_(\d+)_(.+)\z/

      # `row:` is the AR Project, used as the source of truth for
      # canonicalizer-volatile fields (accession).
      # `cache:` is a hash supplied by the Exporter that lives for the
      # full run — renderers use it to memoise expensive lookups across
      # renderer instances that share the same v3 record. The default
      # empty hash keeps the renderer trivially testable in isolation.
      def initialize(record:, row: nil, cache: {})
        @record = record
        @row    = row
        @cache  = cache
      end

      # Returns a Nokogiri::XML::Node representing the <Package>.
      def call
        Nokogiri::XML::Builder.new {|xml|
          xml.Package {
            render_project(xml)
            render_submission(xml)
          }
        }.doc.root
      end

      private

      def project_block    = @record.dig('projects', 0) || {}
      def submission_block = @record['submission'] || {}

      def render_project(xml)
        xml.Project {
          xml.Project {
            render_project_id(xml)
            render_project_descr(xml)
            render_project_type(xml)
          }
        }
      end

      # `accession` is in the canonicalizer's volatile-paths list, so it
      # never survives a SubmissionUpdate diff/replay cycle into the
      # materialised v3 record. The AR Project column is authoritative;
      # we fall back to the v3 hash only so unit tests can drive the
      # renderer without spinning up an AR row.
      def render_project_id(xml)
        accession = @row&.accession.presence || project_block['accession'].to_s

        xml.ProjectID {
          xml.ArchiveID(accession:, archive: 'DDBJ')
        }
      end

      def render_project_descr(xml)
        xml.ProjectDescr {
          if (title = project_block['title']).present?
            xml.Title title
          end

          if (description = project_block['description']).present?
            xml.Description description
          end

          render_grants(xml)
          render_publications(xml)
          render_release_date(xml)
          render_relevance(xml)
          render_locus_tag_prefix(xml)
        }
      end

      def render_grants(xml)
        Array(project_block['grants']).each do |g|
          attrs = g['id'].present? ? {GrantId: g['id']} : {}

          xml.Grant(**attrs) {
            xml.Title  g['title']  if g['title'].present?
            xml.Agency g['agency'] if g['agency'].present?
          }
        end
      end

      # The forward Converter folds publications into a flat
      # {status, pubmed_id|doi, title} shape (title is the free text of
      # <Reference>); on the way back we decide which DbType to emit.
      # Reference and DbType are siblings, as D-way writes them
      # (<Reference/><DbType>ePubmed</DbType>).
      def render_publications(xml)
        Array(project_block['publications']).each do |pub|
          id, db_type = if (id = pub['pubmed_id']).present?
            [id, 'ePubmed']
          elsif (id = pub['doi']).present?
            [id, 'eDOI']
          end

          attrs = {id:, status: pub['status'].presence}.compact

          xml.Publication(**attrs) {
            xml.Reference pub['title'].to_s if pub['title'].present? || db_type
            xml.DbType db_type if db_type
          }
        end
      end

      # v3 stores relevance as a flat string-keyed dict; the original XML
      # nests each entry as a sibling element under <Relevance>. The
      # Converter lower-cases the element names, so the XSD's names
      # (ModelOrganism included) are looked up; a key outside them is
      # written as it is.
      def render_relevance(xml)
        relevance = project_block['relevance']
        return if relevance.blank?

        xml.Relevance {
          relevance.each do |key, value|
            xml.send(RELEVANCE_ELEMENTS.fetch(key.to_s, key.to_s), value.to_s)
          end
        }
      end

      # v3 `LocusTagPrefix` is {prefix, biosample_id}; the prefix is the
      # element's text and the BioSample it was declared for its
      # attribute. Records converted before the object form carry bare
      # strings.
      def render_locus_tag_prefix(xml)
        Array(project_block['locus_tag_prefix']).each do |entry|
          prefix, biosample_id = entry.is_a?(Hash) ? entry.values_at('prefix', 'biosample_id') : [entry, nil]

          emit_tag(xml, :LocusTagPrefix, prefix, {biosample_id:}.compact)
        end
      end

      # The forward Converter sources hold_date from
      # ProjectDescr/ProjectReleaseDate. We restore the same slot.
      def render_release_date(xml)
        date = submission_block['hold_date']
        xml.ProjectReleaseDate date if date.present?
      end

      # The AR Project's type is authoritative (like the accession); the
      # record's field only stands in when the renderer runs without a row.
      def render_project_type(xml)
        project_type = @row&.project_type.presence || project_block['project_type']

        xml.ProjectType {
          if project_type == 'umbrella'
            render_project_type_top_admin(xml)
          else
            render_project_type_submission(xml, project_block['target'] || {})
          end
        }
      end

      # An umbrella project groups others; the Converter reads its subtype
      # (and the description an "other" subtype requires) from here, and
      # its organism from wherever the XML put one.
      def render_project_type_top_admin(xml)
        attrs = {subtype: project_block['umbrella_subtype'].presence}.compact

        xml.ProjectTypeTopAdmin(**attrs) {
          render_organism(xml)

          if (description = project_block['umbrella_subtype_description']).present?
            xml.DescriptionSubtypeOther description
          end
        }
      end

      def render_project_type_submission(xml, target)
        xml.ProjectTypeSubmission {
          render_target(xml, target)
          render_method(xml, target)
          render_objectives(xml, target)
          render_project_data_types(xml)
        }
      end

      def render_target(xml, target)
        attrs = {
          sample_scope: target['sample_scope'].presence,
          material:     target['material'].presence,
          capture:      target['capture'].presence
        }.compact

        xml.Target(**attrs) {
          render_organism(xml)
          render_provider(xml)
          xml.Description target['description'] if target['description'].present?
        }
      end

      # Nothing when the record has no organism at all (no name, taxID or
      # organism attribute), rather than an empty <Organism/>.
      def render_organism(xml)
        organism = project_block['organism'] || {}
        return if organism.empty? && !organism_attributes?

        attrs = organism['taxonomy_id'] ? {taxID: organism['taxonomy_id'].to_s} : {}

        xml.Organism(**attrs) {
          xml.OrganismName organism['name'] if organism['name'].present?

          render_organism_scalar_attrs(xml)
          render_biological_properties(xml)
          render_organism_post_bp_attrs(xml)
          render_replicon_set(xml)
          render_genome_size(xml)
        }
      end

      # Identity-level scalars that sit directly under Organism, OUTSIDE
      # BiologicalProperties: Strain, IsolateName, Breed, Cultivar, Label,
      # Supergroup. Pulled from the attribute bag where the forward
      # Converter parked them.
      def render_organism_scalar_attrs(xml)
        %w[Label Strain IsolateName Breed Cultivar Supergroup].each do |element|
          render_organism_scalar(xml, element, element)
        end
      end

      def render_biological_properties(xml)
        morphology  = collect_organism_attrs(%w[Gram Enveloped Shape Endospores Motility].map { "BiologicalProperties/Morphology/#{it}" })
        environment = collect_organism_attrs(%w[Salinity OxygenReq OptimumTemperature TemperatureRange Habitat].map { "BiologicalProperties/Environment/#{it}" })
        phenotype   = collect_organism_attrs(%w[BioticRelationship TrophicLevel Disease].map { "BiologicalProperties/Phenotype/#{it}" })

        return if morphology.empty? && environment.empty? && phenotype.empty?

        xml.BiologicalProperties {
          render_subgroup(xml, 'Morphology',  morphology)
          render_subgroup(xml, 'Environment', environment)
          render_subgroup(xml, 'Phenotype',   phenotype)
        }
      end

      def render_subgroup(xml, name, entries)
        return if entries.empty?

        xml.send(name) {
          entries.each do |element, value|
            xml.send(element, value)
          end
        }
      end

      # Organization (cellularity) and Reproduction live BELOW
      # BiologicalProperties under Organism in the source schema.
      def render_organism_post_bp_attrs(xml)
        %w[Organization Reproduction].each do |element|
          render_organism_scalar(xml, element, element)
        end
      end

      # `xpath` is the key in ORGANISM_SCALAR_ATTRS (relative to Organism);
      # `element` is the XML element name to emit. For top-level identity
      # siblings the two are the same; for BiologicalProperties members
      # the xpath includes the BiologicalProperties/Group/ prefix.
      def render_organism_scalar(xml, element, xpath)
        attr_name = ORGANISM_SCALAR_ATTRS[xpath]
        return unless attr_name

        value = attribute_value(attr_name)
        xml.send(element, value) if value
      end

      # RepliconSet was flattened into replicon_<i>_<field> tuples in the
      # bag. Group by the numeric prefix, sort, then rebuild each
      # <Replicon> with the original Type/Name/Size structure (including
      # the `location` / `isSingle` attributes that lived on Type, and
      # the `units` attribute that lived on Size). Ploidy is a singleton
      # with a `type` attribute.
      def render_replicon_set(xml)
        groups = group_replicon_attrs
        ploidy = attribute_value('ploidy')
        return if groups.empty? && ploidy.nil?

        xml.RepliconSet {
          groups.sort_by(&:first).each do |_, fields|
            xml.Replicon {
              render_replicon_type(xml, fields)
              xml.Name fields['name'] if fields['name']
              render_replicon_size(xml, fields)
            }
          end

          xml.Ploidy(type: ploidy) if ploidy
        }
      end

      def render_replicon_type(xml, fields)
        attrs = {location: fields['location'], isSingle: fields['is_single']}.compact

        emit_tag(xml, :Type, fields['type'], attrs)
      end

      def render_replicon_size(xml, fields)
        attrs = {units: fields['size_unit']}.compact

        emit_tag(xml, :Size, fields['size'], attrs)
      end

      # Emit `<Name attr=...>body</Name>` if there's body text;
      # `<Name attr=.../>` if only attrs; nothing at all if both are
      # empty. Centralises the "is this tag worth rendering" decision so
      # the Type / Size paths don't each re-derive it.
      def emit_tag(xml, name, body, attrs)
        return if body.nil? && attrs.empty?

        if body.nil?
          xml.send(name, **attrs)
        else
          xml.send(name, **attrs) { xml.text body.to_s }
        end
      end

      def group_replicon_attrs
        groups = Hash.new {|h, k| h[k] = {} }

        Array(project_block['attributes']).each do |a|
          next unless (m = a['name'].to_s.match(REPLICON_INDEX_RE))

          idx  = m[1].to_i
          field = m[2]
          groups[idx][field] = a['value']
          groups[idx]['size_unit'] = a['unit'] if field == 'size' && a['unit']
        end

        groups
      end

      def render_genome_size(xml)
        attr = find_attribute('genome_size')
        return unless attr

        attrs = attr['unit'] ? {units: attr['unit']} : {}
        xml.GenomeSize(**attrs) { xml.text(attr['value']) }
      end

      def render_provider(xml)
        value = attribute_value('provider')
        xml.Provider value if value
      end

      # The body is the description an "eOther" method requires.
      def render_method(xml, target)
        method_type = target['method']
        return if method_type.blank?

        emit_tag(xml, :Method, target['method_description'].presence, {method_type:})
      end

      # `target.data_types` is the Objectives/Data@data_type vocabulary
      # (eSequence, eRawSequenceReads, …), each with the description an
      # "eOther" choice requires. It is NOT ProjectDataTypeSet, which uses
      # a different vocabulary ("Genome Sequencing", …) and which the
      # Converter parks in `project_data_type` attributes.
      def render_objectives(xml, target)
        data_types = objective_data_types(target)
        return if data_types.empty?

        descriptions = target['data_type_descriptions'] || {}

        xml.Objectives {
          data_types.each do |data_type|
            emit_tag(xml, :Data, descriptions[data_type].presence, {data_type:})
          end
        }
      end

      def render_project_data_types(xml)
        values = project_data_types
        return if values.empty?

        xml.ProjectDataTypeSet {
          values.each do |value|
            xml.DataType value
          end
        }
      end

      # Records converted before the two vocabularies were told apart hold
      # the ProjectDataTypeSet values in `target.data_types` and have no
      # `project_data_type` attributes. For those, values outside the
      # Objectives vocabulary go back to ProjectDataTypeSet.
      def legacy_data_types? = project_data_type_attrs.empty?

      def objective_data_types(target)
        data_types = Array(target['data_types'])

        legacy_data_types? ? data_types.select { OBJECTIVE_DATA_TYPES.include?(it) } : data_types
      end

      def project_data_types
        return project_data_type_attrs unless legacy_data_types?

        Array(project_block.dig('target', 'data_types')).reject { OBJECTIVE_DATA_TYPES.include?(it) }
      end

      def project_data_type_attrs
        Array(project_block['attributes']).filter_map { it['value'] if it['name'] == 'project_data_type' }
      end

      def render_submission(xml)
        submitters = Array(submission_block['submitters'])
        return if submitters.empty?

        xml.Submission {
          xml.Submission {
            xml.Description {
              render_organization(xml, submitters)
            }
          }
        }
      end

      # D-way's model: one Organization per submission, shared by all
      # contacts. The forward Converter copies that Organization onto
      # every Person's `organizations[0]`, so we read it back from the
      # first submitter that has one.
      def render_organization(xml, submitters)
        org = submitters.lazy.filter_map { it['organizations']&.first }.first || {}

        attrs = {
          type: org['type'].presence,
          role: org['role'].presence,
          url:  org['url'].presence
        }.compact

        xml.Organization(**attrs) {
          xml.Name org['name'] if org['name'].present?

          submitters.each do |s|
            render_contact(xml, s)
          end
        }
      end

      def render_contact(xml, person)
        attrs = person['email'].present? ? {email: person['email']} : {}

        xml.Contact(**attrs) {
          xml.Name {
            xml.First person['first_name'] if person['first_name'].present?
            xml.Last  person['last_name']  if person['last_name'].present?
          }
        }
      end

      # The attributes the Converter reads from under <Organism>.
      def organism_attributes?
        ORGANISM_SCALAR_ATTRS.each_value.any? { find_attribute(it) } ||
          %w[ploidy genome_size].any? { find_attribute(it) } ||
          group_replicon_attrs.any?
      end

      def collect_organism_attrs(xpaths)
        xpaths.filter_map {|xpath|
          attr_name = ORGANISM_SCALAR_ATTRS[xpath]
          next nil unless attr_name

          value = attribute_value(attr_name)
          next nil unless value

          [xpath.split('/').last, value]
        }
      end

      def attribute_value(name)
        find_attribute(name)&.[]('value')
      end

      # Build the name → attribute index once per renderer instance.
      # collect_organism_attrs alone fans this out into 13 lookups; the
      # naive `Array(...).find` would be O(N) per lookup against an
      # organism that easily carries 20+ bag attributes.
      def find_attribute(name)
        attrs_by_name[name]
      end

      def attrs_by_name
        @attrs_by_name ||= Array(project_block['attributes']).index_by { it['name'] }
      end
    end
  end
end
