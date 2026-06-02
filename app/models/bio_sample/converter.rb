# frozen_string_literal: true

module BioSample
  # D-way BioSample EAV → DDBJ Record v3 hash. Phase 5 spike scope:
  # enough fields to drive the admin show page (1 submission with N
  # samples in the samples array).
  #
  # Well-known attributes (organism, taxonomy_id, sample_title) are
  # lifted out of the EAV bag into v3-typed sample fields for
  # convenience; the same value also survives in
  # samples[*].attributes. Blank-value EAV rows ARE dropped from the
  # attribute bag for canonicalisation cleanliness; an audit comparing
  # D-way row counts to v3 attribute counts will disagree on those
  # placeholder rows. Phase 6 should decide whether to keep blanks
  # (faithful row-count audit) or strip them (cleaner v3 records).
  class Converter
    SOURCE_FORMAT = 'dway_bs_eav'

    def initialize(submission:)
      @submission = submission
    end

    def call
      {
        'schema_version' => 'v3',
        'provenance'     => {'source_format' => SOURCE_FORMAT},
        'submission'     => submission_block,
        'samples'        => @submission.samples.map {|s| sample_block(s) }
      }.compact
    end

    private

    def submission_block
      block = {
        'submitters' => @submission.contacts.map {|c|
          {'email' => c.email, 'first' => c.first, 'last' => c.last}.compact.presence
        }.compact,
        'comments'   => @submission.comment
      }.compact.reject {|_, v| v.respond_to?(:empty?) && v.empty? }

      block.presence
    end

    def sample_block(sample)
      attrs_by_name = sample.attributes.to_h {|a| [a['name'], a['value']] }

      {
        'accession' => sample.accession,
        'alias'     => sample.sample_name,
        'title'     => attrs_by_name['sample_title'].presence,
        'package'   => sample.package,
        'organism'  => organism_block(attrs_by_name),
        'attributes' => sample.attributes.filter_map {|a|
          next nil if a['value'].blank?
          {'name' => a['name'], 'value' => a['value']}
        }.presence
      }.compact
    end

    def organism_block(attrs_by_name)
      # `Integer(_, exception: false)` rejects non-numeric staging values
      # ('unknown', 'N/A', 'sp.') by returning nil rather than silently
      # coercing them to 0 via String#to_i.
      tax  = Integer(attrs_by_name['taxonomy_id'].to_s, 10, exception: false)
      name = attrs_by_name['organism'].presence

      return nil unless tax || name

      {
        'taxonomy_id' => tax,
        'name'        => name
      }.compact
    end
  end
end
