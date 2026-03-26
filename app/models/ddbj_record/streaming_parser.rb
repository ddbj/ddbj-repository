# frozen_string_literal: true

module DDBJRecord
  # Two-phase streaming parser for large DDBJ Record JSON files.
  #
  # Unlike Handler (Oj::Saj), this parser handles multi-GB files with
  # entries containing very long sequence strings (750MB+) that crash
  # the SAJ parser.
  #
  # Phase 1: Extract metadata from file header + features from file tail
  # Phase 2: Stream entries one at a time via line-based boundary detection
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
    # For pretty-printed JSON (multi-line), uses indentation-based boundary
    # detection to stream entries without loading everything into memory.
    # This handles multi-GB files with 750MB+ sequence strings that crash
    # Oj::Saj.
    #
    # For minified JSON (single-line), falls back to DDBJRecord.parse which
    # uses Oj::Saj. This is safe because minified files are small (ST.26
    # patent data); large genome files are always pretty-printed by
    # DDBJRecord::Writer.
    def each_entry(&block)
      return enum_for(:each_entry) unless block

      yielded = each_entry_by_indent(&block)

      return if yielded

      record = File.open(@path) { DDBJRecord.parse(it) }
      record.sequences.entries.each(&block)
    end

    private

    def each_entry_by_indent
      inside_entries = false
      entry_indent   = nil
      entry_buf      = nil
      yielded        = false

      File.foreach(@path) do |line|
        unless inside_entries
          inside_entries = true if line.include?('"entries"')
          next
        end

        indent   = line.size - line.lstrip.size
        stripped = line.lstrip

        if entry_indent.nil?
          if stripped.start_with?('{')
            entry_indent = indent
            entry_buf    = +line
          end

          next
        end

        if indent == entry_indent && stripped.start_with?('{')
          entry_buf = +line
        elsif entry_buf
          entry_buf << line

          if indent == entry_indent && stripped.start_with?('}')
            entry_buf.sub!(/,\s*\z/, '')

            yield build_entry_from_hash(Oj.load(entry_buf))

            yielded   = true
            entry_buf = nil
          end
        elsif stripped.start_with?(']')
          break
        end
      end

      yielded
    end

    private

    def extract_features
      tail_size = [File.size(@path), DEFAULT_TAIL_SIZE].min

      File.open(@path) do |f|
        f.seek(-tail_size, IO::SEEK_END)

        tail  = f.read
        match = tail.match(/"features"\s*:\s*/)

        raise "features key not found in last #{tail_size} bytes of #{@path}" unless match

        json           = tail[match.end(0)..].sub(/\]\s*\}\s*\z/, ']')
        raw_features   = Oj.load(json)

        raw_features.map {|h| build_feature_from_hash(h) }
      end
    end

    def build_entry_from_hash(h)
      h['source_features'] = (h['source_features'] || []).map {|sf|
        sf['source'] = build_source(sf['source']) if sf['source']

        build_source_feature(sf)
      }

      build_entry(h)
    end

    def build_feature_from_hash(h)
      h['qualifiers'] = (h['qualifiers'] || {}).transform_values {|vals|
        vals.map {|q| build_qualifier(q) }
      }

      build_feature(h)
    end
  end
end
