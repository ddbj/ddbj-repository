# frozen_string_literal: true

require 'json/canonicalization'

module DDBJRecord
  module Canonicalizer
    # Thin wrapper around the `json-canonicalization` gem so the rest of the
    # codebase only depends on our own surface. Verified byte-identical to
    # Python `rfc8785` 0.1.4 on the spike-0-3 fixture set; gem internally
    # calls `::JSON.generate` and bypasses ActiveSupport's `String#to_json`.
    module JcsAdapter
      # Serialize a fully-normalised value tree to canonical UTF-8 bytes per
      # RFC 8785. Caller MUST have already applied §2 / §3 transforms — JCS
      # only handles key sort + number formatting + string escape.
      def self.dump(value)
        s = value.to_json_c14n
        s = +s if s.frozen?
        s.force_encoding(Encoding::UTF_8)
      end
    end
  end
end
