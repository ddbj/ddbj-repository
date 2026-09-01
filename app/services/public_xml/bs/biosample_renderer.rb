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
    #
    # Everything else in the file is the XML D-way stored per accession:
    # `makePubicXml` concatenates `mass.xml.content` verbatim and strips
    # only Contacts. So the shape to reproduce is bscommon's `Db2Jaxb`,
    # and `test/services/public_xml/bs/biosample_renderer_test.rb` checks
    # the result against both a real stored file and the schema.
    #
    # Two things D-way published that we cannot: `<Links>` (from
    # `mass.publications` and `mass.link`) and the non-primary `<Id>`s
    # (from `mass.ext_ref`). Those tables are simply not read by
    # BioSample::StagingClient, so the values are absent from v3 — the
    # gap is at import, and closing it is what would let this renderer
    # emit them.
    class BioSampleRenderer
      # The names `Db2Jaxb` lifts out of the attribute bag into
      # <Description>, in the order it lifts them. `sample_name` is here
      # too: D-way pops it like the rest and then puts it back at the
      # head of the bag ("Attribute Element で再利用するので、戻して
      # おく"), which is what `publishable_attributes` reproduces.
      LIFTED_ATTRIBUTES = %w[sample_title sample_name organism taxonomy_id description sample_comment].freeze

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

        bag          = Array(sample['attributes']).select { publishable?(it) }
        lifted, rest = lift(bag, sample['alias'])

        Nokogiri::XML::Builder.new {|xml|
          xml.BioSample(**biosample_attrs) {
            render_ids(xml)
            render_description(xml, sample, lifted)
            render_owner(xml)
            render_models(xml, sample)
            render_attributes(xml, rest)
          }
        }.doc.root
      end

      private

      # `publication_date` is the first-publish date; `last_update` is
      # the most recent re-publish, and falls back to `modified_date`
      # rather than to the release — a record corrected but never
      # re-distributed was last updated on the day it was corrected, and
      # that is the value a consumer polls to decide whether to re-fetch
      # (BioSampleConverter.java:29-36).
      #
      # `access` is a constant: BioSample takes no controlled-access
      # data, so D-way stamps every record public. The accession is NOT
      # an attribute here — it goes in `Ids/Id[@namespace="BioSample"]`,
      # which is where the schema puts it and where readers look.
      #
      # NOTE: both dates are `xs:dateTime` and D-way emitted real
      # timestamps, because its columns are timestamps. Ours are `date`
      # — `BioSample::StagingClient` casts `release_date::date` on the
      # way in — so the time of day is not lost here, it was dropped at
      # import and is still in D-way. Midnight is a placeholder for a
      # time we do not have; a date alone is not a `dateTime` at all and
      # would fail the schema on every record in the file. Recovering it
      # means widening the columns and re-importing.
      def biosample_attrs
        {
          access:           'public',
          publication_date: as_datetime(@sample.release_date),
          last_update:      as_datetime(@sample.dist_date || @sample.modified_date)
        }.compact
      end

      def as_datetime(date)
        date&.to_date&.in_time_zone&.iso8601
      end

      # Match on `alias` (== sample_name). ddbj-canon/v2 would also allow
      # joining on `accession`, but `alias` is present from the moment the
      # record exists whereas an accession appears only once issued — and
      # this renderer runs over records at every stage.
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

      # An attribute row says something only if it has both halves
      # (AttributeConverter#hasValue).
      def publishable?(attribute)
        attribute['name'].to_s.strip.present? && attribute['value'].to_s.strip.present?
      end

      # `AttributesOperator#pop`: the FIRST row of each lifted name comes
      # out of the bag, later rows with the same name stay in it. Taking
      # them all out would drop a value that D-way published, and taking
      # the last one would put a different value in <Description> than
      # D-way did.
      #
      # `sample_name` goes straight back to the head of what is left, so
      # it is both the <SampleName> element and the first <Attribute> —
      # the same string in both places, as it was in D-way, where the
      # very same object was re-inserted.
      # A bag with no `sample_name` row of its own gets one made from the
      # alias, which is the same value: D-way meant to do this too and
      # the code is there, but the bean it builds is never added to the
      # list, so it never took effect (DescriptionConverter.java:144).
      # Written out, it also means <Attributes> is never empty — and the
      # element is required, so a sample whose whole bag was lifted would
      # otherwise produce a file no consumer can validate.
      def lift(bag, alias_name)
        taken = {}

        rest = bag.reject {|attribute|
          name = attribute['name']

          next false unless LIFTED_ATTRIBUTES.include?(name) && !taken.key?(name)

          taken[name] = attribute
          true
        }

        taken['sample_name'] ||= {'name' => 'sample_name', 'value' => alias_name} if alias_name.present?

        rest.unshift(taken['sample_name']) if taken.key?('sample_name')

        [taken.transform_values { it['value'].to_s }, rest]
      end

      # The accession, and nothing else — see the class comment on
      # `mass.ext_ref`.
      def render_ids(xml)
        xml.Ids {
          xml.Id(namespace: 'BioSample', is_primary: '1') { xml.text @sample.accession.to_s }
        }
      end

      # Order is the schema's: SampleName, Title, Organism, Comment.
      #
      # Each value is read from the bag first and from the v3 typed slot
      # only as a fallback, because the bag is what D-way lifted from and
      # `BioSample::Converter` fills the typed slots by copying it. Read
      # the other way round, a name this renderer removes from
      # <Attributes> could go unrendered — which is how `sample_comment`,
      # a name with no typed slot at all, disappeared from the file
      # entirely.
      def render_description(xml, sample, lifted)
        paragraphs = [lifted['description'] || sample['description'], lifted['sample_comment']].compact_blank

        xml.Description {
          name  = lifted['sample_name']  || sample['alias']
          title = lifted['sample_title'] || sample['title']

          xml.SampleName name  if name.present?
          xml.Title      title if title.present?

          render_organism(xml, sample, lifted)

          unless paragraphs.empty?
            xml.Comment {
              paragraphs.each { xml.Paragraph it }
            }
          end
        }
      end

      # <OrganismName> is written even when there is no organism, empty.
      # D-way does it deliberately: the element is required, and a sample
      # missing its organism should reach the validator and be told so
      # rather than fail schema parsing first (DescriptionConverter's
      # ORGANISM_ATTRIBUTE comment).
      #
      # `taxonomy_id` is `xs:positiveInteger`, so a staging value that is
      # not one ('unknown', 'N/A', '0') is no more publishable than a
      # missing one.
      def render_organism(xml, sample, lifted)
        organism = sample['organism'] || {}
        name     = lifted['organism']    || organism['name']
        tax      = lifted['taxonomy_id'] || organism['taxonomy_id']
        tax      = Integer(tax.to_s, 10, exception: false)

        xml.Organism(**(tax&.positive? ? {taxonomy_id: tax.to_s} : {})) {
          xml.OrganismName name.to_s
        }
      end

      # Owner without Contacts — bsbatch strips Contacts in public XML
      # output. Name comes from the submission's organization block,
      # which the BS Converter copies onto every submitter's
      # organizations[0] (D-way: one org per submission).
      #
      # Written even when the submission names no organization: <Owner>
      # is required, and D-way emitted an empty <Name> rather than drop
      # it (OrganizationConverter).
      def render_owner(xml)
        org = first_organization || {}

        xml.Owner {
          xml.Name(**{url: org['url'].presence}.compact) { xml.text org['name'].to_s }
        }
      end

      def first_organization
        submitters = Array(@record.dig('submission', 'submitters'))
        submitters.lazy.filter_map { it['organizations']&.first }.first
      end

      # <Models><Model>, not <Package>: the composed package name is what
      # D-way writes here (ModelConverter, from the same
      # `AttributeValidator.createPackage` rule that BioSample::Converter
      # mirrors), and <Package> is not in the schema at all.
      def render_models(xml, sample)
        xml.Models {
          xml.Model sample['package'].to_s
        }
      end

      # Whatever the lift left behind, `sample_name` first.
      def render_attributes(xml, attrs)
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
