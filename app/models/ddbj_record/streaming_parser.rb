# frozen_string_literal: true

module DDBJRecord
  # Streaming parser for large DDBJ Record JSON files.
  #
  # Uses Oj.sc_parse (ScHandler) for true streaming. Entries are yielded
  # one at a time; memory usage is proportional to the largest single
  # entry, not the total file size.
  #
  # Metadata and features are collected in a lightweight first pass
  # (entries discarded), then entries are streamed in subsequent passes.
  class StreamingParser
    include Builders

    def initialize(path)
      @path = path.to_s
    end

    # Returns a DDBJRecord::Root with sequences.entries=[] and features=[].
    def metadata
      ensure_root_parsed

      @metadata
    end

    # Returns Hash[String => Array[DDBJRecord::Feature]]
    def features_by_sequence_id
      ensure_root_parsed

      @features_by_sequence_id
    end

    # Yields DDBJRecord::Entry objects one at a time.
    def each_entry(&block)
      return enum_for(:each_entry) unless block

      handler = EntryStreamHandler.new {|h| block.call(build_entry_from_hash(h)) }

      File.open(@path) {|f| Oj.sc_parse(handler, f) }
    end

    private

    # First pass: parse the entire file with sc_parse, discarding entry
    # data. This collects metadata (submission, experiments, etc.) and
    # features with minimal memory since entry sequences are not retained.
    def ensure_root_parsed
      return if @root_parsed

      handler = EntryStreamHandler.new { } # discard entries

      File.open(@path) {|f| Oj.sc_parse(handler, f) }

      root = handler.result

      @metadata = build_metadata(root)

      @features_by_sequence_id = (root['features'] || [])
        .map {|h| build_feature_from_hash(h) }
        .group_by(&:sequence_id)

      @root_parsed = true
    end

    # Convert raw root hash to DDBJRecord::Root with proper Data objects.
    # Entries and features are set to empty (they are handled separately).
    def build_metadata(root)
      build_root(
        'schema_version' => root['schema_version'],
        'provenance'     => root['provenance'] && build_provenance_deep(root['provenance']),
        'submission'     => root['submission'] && build_submission_deep(root['submission']),
        'experiments'    => (root['experiments'] || []).map {|e| build_experiment_deep(e) },
        'st26'           => root['st26'] && build_st26_deep(root['st26']),
        'sequences'      => build_sequences(
          'common_source' => root.dig('sequences', 'common_source') && build_source_deep(root.dig('sequences', 'common_source')),
          'entries'       => []
        ),
        'features'       => []
      )
    end

    def build_provenance_deep(h)
      build_provenance(h)
    end

    def build_submission_deep(h)
      h = h.dup

      h['submitters'] = Array.wrap(h['submitters']).map {|p|
        build_person_deep(p)
      }

      h['db_xrefs']   = Array.wrap(h['db_xrefs']).map {|x| build_xref(x) }
      h['references'] = Array.wrap(h['references']).map {|r|
        r = r.dup

        r['authors']     = Array.wrap(r['authors']).map {|p| build_person_deep(p) }
        r['consortiums'] = r['consortiums'] && Array.wrap(r['consortiums']).map {|o| build_organization_deep(o) }

        build_reference(r)
      }

      h['application_identification'] = build_application_identification(h['application_identification']) if h['application_identification']

      h['earliest_priority_application_identifications'] = Array.wrap(h['earliest_priority_application_identifications']).map {|a|
        build_application_identification(a)
      }

      build_submission(h)
    end

    def build_person_deep(h)
      h = h.dup
      h['organization'] = h['organization'] && Array.wrap(h['organization']).map {|o| build_organization_deep(o) }
      build_person(h)
    end

    def build_organization_deep(h)
      h = h.dup
      h['address'] = build_address(h['address']) if h['address']
      build_organization(h)
    end

    def build_experiment_deep(h)
      h = h.dup
      h['design']   = h['design'] && build_design_deep(h['design'])
      h['platform'] = h['platform'] && build_platform(h['platform'])
      build_experiment(h)
    end

    def build_design_deep(h)
      h = h.dup
      h['library_layout'] = h['library_layout'] && build_library_layout(h['library_layout'])
      h['targeted_loci']  = (h['targeted_loci'] || []).map {|t| build_targeted_locus(t) } if h['targeted_loci']
      build_design(h)
    end

    def build_st26_deep(h)
      h = h.dup
      h['applicant_names']  = (h['applicant_names'] || []).map {|t| build_localized_text(t) }
      h['inventor_names']   = (h['inventor_names'] || []).map {|t| build_localized_text(t) }
      h['invention_titles'] = (h['invention_titles'] || []).map {|t| build_localized_text(t) }
      build_st26(h)
    end

    def build_source_deep(h)
      h = h.dup
      h['qualifiers'] = build_qualifiers(h['qualifiers'])
      build_source(h)
    end

    def build_entry_from_hash(h)
      h['source_features'] = (h['source_features'] || []).map {|sf|
        if sf['source']
          sf = sf.dup
          sf['source'] = build_source_deep(sf['source'])
        end

        build_source_feature(sf)
      }

      build_entry(h)
    end

    def build_feature_from_hash(h)
      h = h.dup
      h['qualifiers'] = build_qualifiers(h['qualifiers'])
      build_feature(h)
    end

    def build_qualifiers(quals)
      (quals || {}).transform_values {|vals|
        vals.map {|q| q.is_a?(DDBJRecord::Qualifier) ? q : build_qualifier(q) }
      }
    end

    # Oj::ScHandler that streams entries via callback without
    # accumulating them. All other content is built as Hash/Array.
    # After parsing, #result returns the root hash (entries excluded).
    class EntryStreamHandler < Oj::ScHandler
      ENTRIES = Object.new.freeze

      attr_reader :result

      def initialize(&on_entry)
        @on_entry       = on_entry
        @pending_key    = nil
        @hash_key_stack = []
        @result         = nil
      end

      def hash_start
        @hash_key_stack.push @pending_key
        @pending_key = nil

        h = {}
        @result = h if @hash_key_stack.size == 1
        h
      end

      def hash_end
        @hash_key_stack.pop
      end

      def hash_key(key)
        @pending_key = key
        key
      end

      def hash_set(hash, key, value)
        hash[key] = value unless value.equal?(ENTRIES)
      end

      def array_start
        if @pending_key == 'entries' && @hash_key_stack.last == 'sequences'
          @pending_key = nil
          ENTRIES
        else
          @pending_key = nil
          []
        end
      end

      def array_end = nil

      def array_append(array, value)
        if array.equal?(ENTRIES)
          @on_entry.call(value)
        else
          array << value
        end
      end

      def add_value(value) = nil
    end
  end
end
