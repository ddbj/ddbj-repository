# frozen_string_literal: true

module DDBJRecord
  # Lightweight peek at the head of a DDBJ Record JSON IO to decide which
  # parser to dispatch (v2 vs v3). The marker MUST live in the first
  # HEAD_LEN bytes — v3 producers are contracted to emit `schema_version`
  # early; canonicalization sorts keys, so canonical v3 documents tend to
  # have it well past position 0 (after `access_control`, `analyses`, …).
  # That's why we probe a generous window and fall back to a v3-key sniff.
  module SchemaVersionDetector
    # Look-behind avoids matching `"my_schema_version"` etc.
    PATTERN  = /(?<![A-Za-z0-9_])"schema_version"\s*:\s*"v(\d+)/.freeze
    HEAD_LEN = 65_536
    BOM      = "\xEF\xBB\xBF".b.freeze

    # Top-level keys that exist ONLY in v3 (per
    # ddbj-record-specifications/docs/v3-schema.md). Their presence in the
    # head window with no `schema_version` marker is a strong signal we are
    # looking at v3, not legacy.
    V3_KEY_PATTERN = /
      (?<![A-Za-z0-9_])"(?:
        access_control | analyses | assembly | datasets | project |
        samples        | runs     | relations
      )"\s*:
    /xo.freeze

    class FutureSchemaVersionError    < StandardError; end
    class AmbiguousSchemaVersionError < StandardError; end

    SUPPORTED_MAJOR = %w[2 3].freeze
    DEFAULT_MAJOR   = '2'

    # When `schema_version` is present we trust it directly. When it is
    # absent we default to v2 (legacy fixtures and pre-v3 producers ship no
    # marker), BUT if the head window already shows a v3-only top-level key
    # we raise rather than silently dispatch a v3 document into the v2
    # parser. Callers pass a rewindable IO; we read but do not consume.
    def self.detect(io)
      head = io.read(HEAD_LEN).to_s.b

      head = head.byteslice(BOM.bytesize..-1) || +'' if head.start_with?(BOM)

      if (match = head.match(PATTERN))
        major = match[1]

        raise FutureSchemaVersionError, "schema_version v#{major} not supported by this build" unless SUPPORTED_MAJOR.include?(major)

        return [major, head]
      end

      if head.match?(V3_KEY_PATTERN)
        raise AmbiguousSchemaVersionError,
              "schema_version marker missing from first #{HEAD_LEN} bytes, " \
              'but the document contains v3-only top-level keys — emit ' \
              '"schema_version": "v3" earlier in the document.'
      end

      [DEFAULT_MAJOR, head]
    end
  end
end
