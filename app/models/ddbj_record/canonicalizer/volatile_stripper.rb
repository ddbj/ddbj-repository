# frozen_string_literal: true

module DDBJRecord
  module Canonicalizer
    # Strip volatile sub-trees (provenance, server-assigned accessions,
    # last_update, etc.) prior to diffing so curator-driven changes are not
    # drowned out by archive-internal updates. Operates on a plain hash/array
    # tree post-StringNormalizer; mutates a deep copy and returns it.
    module VolatileStripper
      module_function

      def strip(value, pointer: '')
        case value
        when Hash
          out = {}

          value.each do |k, v|
            child_pointer = "#{pointer}/#{escape_pointer_segment(k)}"
            next if PathClassifier.volatile?(child_pointer)

            stripped = strip(v, pointer: child_pointer)
            out[k]   = stripped unless EmptyDropper.empty?(stripped)
          end

          out
        when Array
          value.each_with_index.filter_map {|element, idx|
            child_pointer = "#{pointer}/#{idx}"
            next nil if PathClassifier.volatile?(child_pointer)

            stripped = strip(element, pointer: child_pointer)
            stripped unless EmptyDropper.empty?(stripped)
          }
        else
          value
        end
      end

      # RFC 6901 §4 — `~` → `~0`, `/` → `~1`. Order matters.
      # @api private
      def escape_pointer_segment(seg)
        seg.to_s.gsub('~', '~0').gsub('/', '~1')
      end
    end
  end
end
