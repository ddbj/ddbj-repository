# frozen_string_literal: true

require_relative 'data'

module DDBJRecord
  class Handler < Oj::Saj
    attr_reader :result

    HASH_CHILD = {
      root: {
        'submission' => :submission,
        'st26'       => :st26,
        'sequences'  => :sequences,
        'features'   => :features
      },

      submission: {
        'application_identification'                    => :application_identification,
        'earliest_priority_application_identifications' => :earliest_priority_application_identifications
      },

      st26: {
        'applicant_names'  => :localized_texts,
        'inventor_names'   => :localized_texts,
        'invention_titles' => :localized_texts
      },

      sequences: {
        'entries' => :entries
      },

      entry: {
        'source_qualifiers' => :qualifier_dict
      },

      feature: {
        'qualifiers' => :qualifier_dict
      },

      qualifier_dict: :qualifier_list
    }.freeze

    ARRAY_ELEMENT = {
      features:                                        :feature,
      entries:                                         :entry,
      localized_texts:                                 :localized_text,
      qualifier_list:                                  :qualifier,
      earliest_priority_application_identifications:   :application_identification
    }.freeze

    BUILDERS = {
      root:                       :build_root,
      submission:                 :build_submission,
      st26:                       :build_st26,
      sequences:                  :build_sequences,
      entry:                      :build_entry,
      feature:                    :build_feature,
      qualifier:                  :build_qualifier,
      localized_text:             :build_localized_text,
      application_identification: :build_application_identification
    }.freeze

    def initialize
      @result = nil
      @stack  = []
    end

    def hash_start(key)
      @stack.push [:hash, {}, resolve_type(key)]
    end

    def hash_end(key)
      _, h, type = @stack.pop
      value      = BUILDERS[type]&.then { send(it, h) } || h

      push_value value, key
    end

    def array_start(key)
      @stack.push [:array, [], resolve_type(key)]
    end

    def array_end(key)
      _, a, _ = @stack.pop

      push_value a, key
    end

    def add_value(value, key)
      value.freeze if value.is_a?(String)

      push_value value, key
    end

    def error(message, line, column)
      raise Oj::ParseError, "#{message} at line #{line}, column #{column}"
    end

    private

    def resolve_type(key)
      return :root if @stack.empty?

      _, _, parent_type = @stack.last

      if key.nil?
        ARRAY_ELEMENT[parent_type]
      else
        children = HASH_CHILD[parent_type]

        case children
        when Hash
          children[key]
        when Symbol
          children
        end
      end
    end

    def push_value(value, key)
      if @stack.empty?
        @result = value
        return
      end

      kind, container, = @stack.last

      if kind == :hash
        container[key] = value
      else
        container << value
      end
    end

    def build_root(h)
      Root.new(
        schema_version: h['schema_version'],
        submission:     h['submission'],
        st26:           h['st26'],
        sequences:      h['sequences'],
        features:       h['features'] || []
      )
    end

    def build_submission(h)
      Submission.new(
        application_identification:                    h['application_identification'],
        division:                                      h['division'],
        earliest_priority_application_identifications: h['earliest_priority_application_identifications'],
        publication_date:                              h['publication_date'],
        applicant_name:                                h['applicant_name'],
        invention_title:                               h['invention_title'],
        inventor_name:                                 h['inventor_name']
      )
    end

    def build_st26(h)
      St26.new(
        applicant_names:      h['applicant_names'] || [],
        applicant_name_latin: h['applicant_name_latin'],
        inventor_names:       h['inventor_names'] || [],
        inventor_name_latin:  h['inventor_name_latin'],
        invention_titles:     h['invention_titles'] || []
      )
    end

    def build_sequences(h)
      Sequences.new(
        entries: h['entries'] || []
      )
    end

    def build_entry(h)
      Entry.new(
        id:                h['id'],
        sequence:          h['sequence'],
        length:            h['length'],
        location:          h['location'],
        topology:          h['topology'],
        definition:        h['definition'],
        tax_id:            h['tax_id'],
        source_qualifiers: h['source_qualifiers'] || {},
        accession:         h['accession'],
        locus:             h['locus'],
        version:           h['version'],
        last_updated:      h['last_updated']
      )
    end

    def build_feature(h)
      Feature.new(
        id:           h['id'],
        type:         h['type'],
        location:     h['location'],
        sequence_id:  h['sequence_id'],
        qualifiers:   h['qualifiers'] || {},
        locus_tag_id: h['locus_tag_id']
      )
    end

    def build_qualifier(h)
      Qualifier.new(
        id:    h['id'],
        value: h['value']
      )
    end

    def build_localized_text(h)
      LocalizedText.new(
        language_code: h['language_code'],
        text:          h['text']
      )
    end

    def build_application_identification(h)
      ApplicationIdentification.new(
        filing_date:             h['filing_date'],
        ip_office_code:          h['ip_office_code'],
        application_number_text: h['application_number_text']
      )
    end
  end
end
