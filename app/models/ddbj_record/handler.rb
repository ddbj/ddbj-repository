# frozen_string_literal: true

module DDBJRecord
  class Handler < Oj::Saj
    attr_reader :result

    HASH_CHILD = {
      root: {
        'provenance' => :provenance,
        'submission' => :submission,
        'st26'       => :st26,
        'sequences'  => :sequences,
        'features'   => :features
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

    def build_root(h)
      Root.new(
        schema_version: h['schema_version'],
        provenance:     h['provenance'],
        submission:     h['submission'],
        experiments:    h['experiments'] || [],
        st26:           h['st26'],
        sequences:      h['sequences'],
        features:       h['features'] || []
      )
    end

    def build_provenance(h)
      known = %w[source_format]
      extras = h.except(*known)

      Provenance.new(
        source_format: h['source_format'],
        extras:        extras.empty? ? nil : extras
      )
    end

    def build_submission(h)
      Submission.new(
        submitters:                                    h['submitters'] || [],
        db_xrefs:                                      h['db_xrefs'] || [],
        references:                                    h['references'] || [],
        comments:                                      h['comments'] || [],
        trad_submission_category:                      h['trad_submission_category'],
        division:                                      h['division'],
        locus_tag_prefix:                              h['locus_tag_prefix'],
        seq_prefix:                                    h['seq_prefix'],
        hold_date:                                     h['hold_date'],
        keywords:                                      h['keywords'],
        datatype:                                      h['datatype'],
        publication_date:                              h['publication_date'],
        applicant_name:                                h['applicant_name'],
        inventor_name:                                 h['inventor_name'],
        invention_title:                               h['invention_title'],
        application_identification:                    h['application_identification'],
        earliest_priority_application_identifications: h['earliest_priority_application_identifications']
      )
    end

    def build_person(h)
      Person.new(
        name:         h['name'],
        abbreviation: h['abbreviation'],
        email:        h['email'],
        orcid:        h['orcid'],
        organization: h['organization']
      )
    end

    def build_organization(h)
      Organization.new(
        name:         h['name'],
        abbreviation: h['abbreviation'],
        url:          h['url'],
        role:         h['role'],
        type:         h['type'],
        department:   h['department'],
        address:      h['address'],
        ror_id:       h['ror_id']
      )
    end

    def build_address(h)
      Address.new(
        country:     h['country'],
        state:       h['state'],
        city:        h['city'],
        street:      h['street'],
        postal_code: h['postal_code']
      )
    end

    def build_xref(h)
      Xref.new(
        db: h['db'],
        id: h['id']
      )
    end

    def build_reference(h)
      Reference.new(
        title:          h['title'],
        authors:        h['authors'] || [],
        consortiums:    h['consortiums'],
        status:         h['status'],
        year:           h['year'],
        journal:        h['journal'],
        volume:         h['volume'],
        issue:          h['issue'],
        start_page:     h['start_page'],
        end_page:       h['end_page'],
        date_published: h['date_published'],
        doi:            h['doi'],
        url:            h['url'],
        pubmed_id:      h['pubmed_id']
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

    def build_experiment(h)
      Experiment.new(
        id:                    h['id'],
        title:                 h['title'],
        design:                h['design'],
        platform:              h['platform'],
        experiment_attributes: h['experiment_attributes'] || {}
      )
    end

    def build_design(h)
      Design.new(
        design_description:           h['design_description'],
        library_name:                 h['library_name'],
        library_strategy:             h['library_strategy'],
        library_source:               h['library_source'],
        library_selection:            h['library_selection'],
        library_layout:               h['library_layout'],
        targeted_loci:                h['targeted_loci'],
        pooling_strategy:             h['pooling_strategy'],
        library_construction_protocol: h['library_construction_protocol']
      )
    end

    def build_library_layout(h)
      LibraryLayout.new(
        layout_type:    h['layout_type'],
        nominal_length: h['nominal_length'],
        nominal_sdev:   h['nominal_sdev']
      )
    end

    def build_targeted_locus(h)
      TargetedLocus.new(
        locus_name:  h['locus_name'],
        description: h['description']
      )
    end

    def build_platform(h)
      Platform.new(
        platform_type:    h['platform_type'],
        instrument_model: h['instrument_model']
      )
    end

    def build_sequences(h)
      Sequences.new(
        common_source: h['common_source'],
        entries:       h['entries'] || []
      )
    end

    def build_source(h)
      Source.new(
        organism:   h['organism'],
        mol_type:   h['mol_type'],
        qualifiers: h['qualifiers'] || {}
      )
    end

    def build_entry(h)
      Entry.new(
        id:              h['id'],
        name:            h['name'],
        type:            h['type'],
        topology:        h['topology'],
        sequence:        h['sequence'],
        comments:        h['comments'],
        source_features: h['source_features'] || [],
        length:          h['length'],
        definition:      h['definition'],
        tax_id:          h['tax_id'],
        accession:       h['accession'],
        locus:           h['locus'],
        version:         h['version'],
        last_updated:    h['last_updated']
      )
    end

    def build_source_feature(h)
      SourceFeature.new(
        id:         h['id'],
        location:   h['location'],
        source:     h['source'],
        definition: h['definition']
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
