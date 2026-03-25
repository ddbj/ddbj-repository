# frozen_string_literal: true

module DDBJRecord
  class Handler < Oj::Saj
    include Builders

    attr_reader :result

    HASH_CHILD = {
      root: {
        'provenance'  => :provenance,
        'submission'  => :submission,
        'experiments' => :experiments,
        'st26'        => :st26,
        'sequences'   => :sequences,
        'features'    => :features
      },

      provenance: nil,

      submission: {
        'application_identification'                    => :application_identification,
        'earliest_priority_application_identifications' => :earliest_priority_application_identifications,
        'submitters'                                    => :submitters,
        'db_xrefs'                                      => :db_xrefs,
        'references'                                    => :references_list
      },

      person: {
        'organization' => :organizations
      },

      organization: {
        'address' => :address
      },

      reference: {
        'authors'     => :persons,
        'consortiums' => :organizations
      },

      st26: {
        'applicant_names'  => :localized_texts,
        'inventor_names'   => :localized_texts,
        'invention_titles' => :localized_texts
      },

      experiment: {
        'design'   => :design,
        'platform' => :platform
      },

      design: {
        'library_layout' => :library_layout,
        'targeted_loci'  => :targeted_loci
      },

      sequences: {
        'common_source' => :source,
        'entries'       => :entries
      },

      source: {
        'qualifiers' => :qualifier_dict
      },

      entry: {
        'source_features' => :source_features
      },

      source_feature: {
        'source' => :source
      },

      feature: {
        'qualifiers' => :qualifier_dict
      },

      qualifier_dict: :qualifier_list
    }.freeze

    ARRAY_ELEMENT = {
      features:                                      :feature,
      entries:                                       :entry,
      source_features:                               :source_feature,
      experiments:                                   :experiment,
      submitters:                                    :person,
      persons:                                       :person,
      organizations:                                 :organization,
      db_xrefs:                                      :xref,
      references_list:                               :reference,
      localized_texts:                               :localized_text,
      targeted_loci:                                 :targeted_locus,
      qualifier_list:                                :qualifier,
      earliest_priority_application_identifications: :application_identification
    }.freeze

    BUILDERS = {
      root:                       :build_root,
      provenance:                 :build_provenance,
      submission:                 :build_submission,
      person:                     :build_person,
      organization:               :build_organization,
      address:                    :build_address,
      xref:                       :build_xref,
      reference:                  :build_reference,
      st26:                       :build_st26,
      experiment:                 :build_experiment,
      design:                     :build_design,
      library_layout:             :build_library_layout,
      targeted_locus:             :build_targeted_locus,
      platform:                   :build_platform,
      sequences:                  :build_sequences,
      source:                     :build_source,
      entry:                      :build_entry,
      source_feature:             :build_source_feature,
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
      value = -value if value.is_a?(String)

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
  end
end
