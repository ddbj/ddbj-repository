# frozen_string_literal: true

module DDBJRecord
  # Streaming parser for large DDBJ Record JSON files.
  #
  # Uses Oj.sc_parse (ScHandler) for true streaming entry enumeration
  # that works with both pretty-printed and minified JSON. Memory usage
  # is proportional to the largest single entry, not the total file size.
  #
  # Phase 1: Extract metadata from file header + features from file tail
  # Phase 2: Stream entries one at a time via Oj.sc_parse
  class StreamingParser
    include Builders

    HEADER_READ_SIZE  = 500_000
    DEFAULT_TAIL_SIZE = 50_000_000

    def initialize(path)
      @path = path.to_s
    end

    # Returns a DDBJRecord::Root with sequences.entries=[] and features=[].
    # Useful for accessing submission, experiments, common_source, etc.
    def metadata
      @metadata ||= begin
        header = File.read(@path, HEADER_READ_SIZE)
        idx    = header.index('"entries"')

        raise "entries key not found in first #{HEADER_READ_SIZE} bytes of #{@path}" unless idx

        mini = header[0...idx] + '"entries": []}, "features": []}'

        DDBJRecord.parse(StringIO.new(mini))
      end
    end

    # Returns Hash[String => Array[DDBJRecord::Feature]]
    def features_by_sequence_id
      @features_by_sequence_id ||= extract_features.group_by(&:sequence_id)
    end

    # Yields DDBJRecord::Entry objects one at a time.
    #
    # Uses Oj.sc_parse with a custom ScHandler that intercepts the
    # entries array and yields each entry hash individually, rather
    # than accumulating all entries in memory.
    def each_entry(&block)
      return enum_for(:each_entry) unless block

      handler = EntryStreamHandler.new {|h| block.call(build_entry_from_hash(h)) }

      File.open(@path) {|f| Oj.sc_parse(handler, f) }
    end

    private

    def extract_features
      tail_size = [File.size(@path), DEFAULT_TAIL_SIZE].min

      File.open(@path) do |f|
        f.seek(-tail_size, IO::SEEK_END)

        tail  = f.read
        match = tail.match(/"features"\s*:\s*/)

        raise "features key not found in last #{tail_size} bytes of #{@path}" unless match

        json = tail[match.end(0)..].sub(/\]\s*\}\s*\z/, ']')

        Oj.load(json).map {|h| build_feature_from_hash(h) }
      end
    end

    def build_entry_from_hash(h)
      h['source_features'] = (h['source_features'] || []).map {|sf|
        if sf['source']
          sf['source']['qualifiers'] = build_qualifiers(sf['source']['qualifiers'])
          sf['source'] = build_source(sf['source'])
        end

        build_source_feature(sf)
      }

      build_entry(h)
    end

    def build_feature_from_hash(h)
      h['qualifiers'] = build_qualifiers(h['qualifiers'])

      build_feature(h)
    end

    def build_qualifiers(quals)
      (quals || {}).transform_values {|vals|
        vals.map {|q| q.is_a?(DDBJRecord::Qualifier) ? q : build_qualifier(q) }
      }
    end

    # Oj::ScHandler that streams entries from the "sequences.entries"
    # array via a callback, without accumulating them in memory.
    # All other JSON content is built normally as nested Hash/Array.
    class EntryStreamHandler < Oj::ScHandler
      ENTRIES = Object.new.freeze

      def initialize(&on_entry)
        @on_entry    = on_entry
        @pending_key = nil
      end

      def hash_start
        @pending_key = nil
        {}
      end

      def hash_end = nil

      def hash_key(key)
        @pending_key = key
        key
      end

      def hash_set(hash, key, value)
        hash[key] = value unless value.equal?(ENTRIES)
      end

      def array_start
        if @pending_key == 'entries'
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
