# frozen_string_literal: true

module BioSample
  # D-way BioSample EAV → DDBJ Record v3 hash. Phase 5 spike scope:
  # enough fields to drive the admin show page (1 submission with N
  # samples in the samples array). EAV-shaped attribute rows survive
  # in `samples[*].attributes`; well-known attributes (organism,
  # taxonomy_id, sample_title, sample comment) are also lifted into
  # the v3-typed sample fields for convenience.
  class Converter
    SOURCE_FORMAT = 'dway_bs_eav'

    # Attribute names that get lifted out of the EAV bag into typed
    # fields on the v3 Sample. The bag still retains them; lifting is
    # convenience, not relocation, so the canonical record carries
    # every original attribute exactly once.
    TYPED_ATTRS = %w[organism taxonomy_id sample_title sample_name].to_set.freeze

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
      tax  = attrs_by_name['taxonomy_id'].presence
      name = attrs_by_name['organism'].presence

      return nil unless tax || name

      {
        'taxonomy_id' => tax&.to_i,
        'name'        => name
      }.compact
    end
  end
end
