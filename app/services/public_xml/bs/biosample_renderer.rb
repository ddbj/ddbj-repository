# frozen_string_literal: true

require 'nokogiri'

module PublicXML
  module Bs
    # Render a single <BioSample> element from a v3 DDBJ Record hash.
    #
    # The v3 record is the parent SUBMISSION's materialised state — a BS
    # submission carries N samples in `record['samples']`. The Exporter
    # iterates one Sample AR row at a time and we pick the matching v3
    # entry by accession.
    #
    # Important deviation from BP: bsbatch's public XML pipeline removes
    # `/BioSample/Owner/Contacts` (active code at BsMakeXml.java:217),
    # so we never emit any Contact children — Owner gets Name only.
    # Phase B is not applicable here (no exchange XML for BS).
    class BioSampleRenderer
      # `cache:` is a hash supplied by the Exporter that lives for the
      # full run. The samples-by-alias index for the parent submission
      # is memoised in it, so renderers for sibling samples of the same
      # submission do not each rebuild the same N-element index — a BS
      # submission with 20K samples would otherwise pay O(N²).
      def initialize(record:, row:, cache: {})
        @record = record
        @sample = row
        @cache  = cache
      end

      def call
        sample = find_sample_v3
        return nil unless sample

        Nokogiri::XML::Builder.new {|xml|
          xml.BioSample(**biosample_attrs) {
            render_ids(xml, sample)
            render_description(xml, sample)
            render_owner(xml)
            render_package(xml, sample)
            render_attributes(xml, sample)
          }
        }.doc.root
      end

      private

      # `publication_date` is the first-publish date, `last_update` is
      # the most recent re-publish. bsbatch sources both from DB columns
      # (release_date / dist_date) rather than the staging XML because
      # the XML's timestamps weren't normalised. We honour the same
      # invariant — dist_date may be nil for a sample that's been
      # published but never re-released, in which case last_update
      # falls back to release_date. `accession` itself is in the
      # canonicalizer's volatile-paths set so the AR column is the
      # only reliable source.
      def biosample_attrs
        {
          accession:        @sample.accession.to_s,
          publication_date: @sample.release_date&.to_date&.iso8601,
          last_update:      (@sample.dist_date || @sample.release_date)&.to_date&.iso8601
        }.compact
      end

      # Match on `alias` (== sample_name) — `accession` would not survive
      # the canonicalizer's volatile strip, so we can't join on it. The
      # `alias` field is curator-input and stable across diffs.
      #
      # The index is keyed by the v3 hash's object_id, which is stable
      # for the duration of the Exporter run because the Exporter
      # memoises materialised_record per submission_id.
      def find_sample_v3
        samples_by_alias[@sample.sample_name]
      end

      def samples_by_alias
        @cache[[:bs_samples_by_alias, @record.object_id]] ||=
          Array(@record['samples']).index_by { it['alias'] }
      end

      def render_ids(xml, sample)
        xml.Ids {
          xml.Id(db: 'DDBJ', is_primary: '1') { xml.text @sample.accession.to_s }

          if sample['alias'].present?
            xml.Id(db_label: 'Sample name') { xml.text sample['alias'] }
          end
        }
      end

      def render_description(xml, sample)
        xml.Description {
          xml.Title sample['title'] if sample['title'].present?

          if sample['description'].present?
            xml.Comment {
              xml.Paragraph sample['description']
            }
          end

          render_organism(xml, sample)
        }
      end

      def render_organism(xml, sample)
        organism = sample['organism'] || {}
        attrs    = organism['taxonomy_id'] ? {taxonomy_id: organism['taxonomy_id'].to_s} : {}

        xml.Organism(**attrs) {
          xml.OrganismName organism['name'] if organism['name'].present?
        }
      end

      # Owner without Contacts — bsbatch strips Contacts in public XML
      # output. Name comes from the submission's organization block,
      # which the BS Converter copies onto every submitter's
      # organizations[0] (D-way: one org per submission).
      def render_owner(xml)
        org = first_organization
        return unless org && org['name'].present?

        xml.Owner {
          xml.Name org['name']
        }
      end

      def first_organization
        submitters = Array(@record.dig('submission', 'submitters'))
        submitters.lazy.filter_map { it['organizations']&.first }.first
      end

      def render_package(xml, sample)
        xml.Package sample['package'] if sample['package'].present?
      end

      def render_attributes(xml, sample)
        attrs = Array(sample['attributes'])
        return if attrs.empty?

        xml.Attributes {
          attrs.each do |a|
            xml.Attribute(attribute_name: a['name']) { xml.text a['value'].to_s }
          end
        }
      end
    end
  end
end
