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

      def project_block    = @record['project']    || {}
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
          render_relevance(xml)
          render_locus_tag_prefix(xml)
          render_release_date(xml)
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
      # {status, pubmed_id|doi} shape; on the way back we have to decide
      # which DbType to emit. A publication that survived the round trip
      # without an id (status-only) gets no Reference child — that's
      # consistent with bpbatch leaving the slot empty.
      def render_publications(xml)
        Array(project_block['publications']).each do |pub|
          id, db_type = if (id = pub['pubmed_id']).present?
            [id, 'ePubmed']
          elsif (id = pub['doi']).present?
            [id, 'eDOI']
          end

          attrs = {id:, status: pub['status'].presence}.compact

          xml.Publication(**attrs) {
            if db_type
              xml.Reference {
                xml.DbType db_type
              }
            end
          }
        end
      end

      # v3 stores relevance as a flat string-keyed dict; the original XML
      # nests each entry as a sibling element under <Relevance>. Element
      # names are lower-cased in v3 but D-way's schema uses TitleCase for
      # well-known categories (Medical, Agricultural, Industrial, ...) and
      # a literal "Other" for free text. We re-uppercase the first letter
      # so consumers that match on element name still hit; bag-mode keys
      # the curator invented stay as-is.
      def render_relevance(xml)
        relevance = project_block['relevance']
        return if relevance.blank?

        xml.Relevance {
          relevance.each do |key, value|
            xml.send(titleize_element(key), value.to_s)
          end
        }
      end

      def render_locus_tag_prefix(xml)
        Array(project_block['locus_tag_prefix']).each do |prefix|
          xml.LocusTagPrefix prefix
        end
      end

      # The forward Converter sources hold_date from
      # ProjectDescr/ProjectReleaseDate. We restore the same slot.
      def render_release_date(xml)
        date = submission_block['hold_date']
        xml.ProjectReleaseDate date if date.present?
      end

      def render_project_type(xml)
        target = project_block['target'] || {}

        xml.ProjectType {
          xml.ProjectTypeSubmission {
            render_target(xml, target)
            render_method(xml, target)
            render_data_types(xml, target)
          }
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
        }
      end

      def render_organism(xml)
        organism = project_block['organism'] || {}
        attrs    = organism['taxonomy_id'] ? {taxID: organism['taxonomy_id'].to_s} : {}

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
        %w[Strain IsolateName Breed Cultivar Label Supergroup].each do |element|
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

      def render_method(xml, target)
        method_type = target['method']
        return if method_type.blank?

        xml.Method(method_type:)
      end

      def render_data_types(xml, target)
        data_types = Array(target['data_types'])
        return if data_types.empty?

        xml.ProjectDataTypeSet {
          data_types.each do |dt|
            xml.DataType dt
          end
        }
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

      def titleize_element(key)
        # Preserve `pH`, `CO2`-style curator keys that already have mixed
        # case. Only TitleCase a fully-lowercase key.
        return key if key.match?(/[A-Z]/)

        key.sub(/\A./, &:upcase)
      end
    end
  end
end
