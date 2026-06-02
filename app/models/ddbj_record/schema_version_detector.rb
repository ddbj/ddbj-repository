# frozen_string_literal: true

module DDBJRecord
  # Lightweight peek at the head of a DDBJ Record JSON IO to decide which
  # parser to dispatch (v2 vs v3). Does not consume the IO — callers receive
  # the version string AND the read bytes so they can re-prepend.
  module SchemaVersionDetector
    # Look-behind avoids matching `"my_schema_version"` etc.
    PATTERN  = /(?<![A-Za-z0-9_])"schema_version"\s*:\s*"v(\d+)/.freeze
    HEAD_LEN = 4096
    BOM      = "\xEF\xBB\xBF".b.freeze

    class FutureSchemaVersionError < StandardError; end

    SUPPORTED_MAJOR = %w[2 3].freeze
    DEFAULT_MAJOR   = '2'

    # When schema_version is absent we default to v2 — the legacy in-tree
    # records (and several test fixtures) predate the field. Only a v3+
    # producer is expected to emit the marker, so the default keeps
    # round-trip parity with everything DDBJRecord shipped before this
    # detector existed.
    def self.detect(io)
      head = io.read(HEAD_LEN).to_s.b

      head = head.byteslice(BOM.bytesize..-1) || +'' if head.start_with?(BOM)

      major = head.match(PATTERN)&.then { it[1] } || DEFAULT_MAJOR

      raise FutureSchemaVersionError, "schema_version v#{major} not supported by this build" unless SUPPORTED_MAJOR.include?(major)

      [major, head]
    end
  end
end
