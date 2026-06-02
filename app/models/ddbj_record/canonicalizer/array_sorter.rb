# frozen_string_literal: true

require 'digest'

module DDBJRecord
  module Canonicalizer
    # Sort an array per its registered mode (§3.1).
    #
    # The sorter is fed already-canonicalised children: each element is a
    # `Normalizer::Result(tree:, bytes:, sha:)` triple where `tree` is the
    # plain Ruby value, `bytes` is its canonical JCS serialization (frozen
    # UTF-8), and `sha` is `Digest::SHA256.hexdigest(bytes)`. We sort
    # `(bytes, sha)` once per pass, never recanonicalising — that is the
    # performance contract from canonical-json.md §3.1.
    module ArraySorter
      module_function

      def sort(results, pointer:)
        rule = PathClassifier.array_rule(pointer)
        mode = rule.fetch('mode')

        case mode
        when 'ordered' then sort_ordered(results, pointer:)
        when 'keyed'   then sort_keyed(results, pointer:, key: rule['key'] || [])
        when 'bag'     then sort_bag(results, pointer:)
        else
          raise UnsupportedValueError, "unknown array mode #{mode.inspect} at #{pointer}"
        end
      end

      def sort_ordered(results, pointer:)
        results.each_with_index do |r, idx|
          if EmptyDropper.empty?(r.tree)
            raise OrderedEmptyElementError,
                  "ordered array #{pointer} contains empty element at index #{idx}; " \
                  'removing would shift downstream JSON Pointer indices'
          end
        end
      end

      def sort_keyed(results, pointer:, key:)
        kept = results.reject {|r| EmptyDropper.empty?(r.tree) }

        decorated = kept.map {|r|
          tuple = key.map {|k| key_component(r.tree, k) }
          [tuple, r.sha, r]
        }

        decorated.sort_by {|tuple, sha, _r| [tuple, sha] }.map {|_, _, r| r }
      end

      def sort_bag(results, pointer:)
        kept = results.reject {|r| EmptyDropper.empty?(r.tree) }
        kept.sort_by(&:sha)
      end

      # Drill into a (potentially nested) keyed-tuple field. The key list may
      # contain `/`-separated subpaths such as `target/db`. Missing or empty
      # components coerce to `''` per §3.1.
      # @api private
      def key_component(tree, path)
        segs = path.to_s.split('/')

        value = segs.reduce(tree) {|acc, seg|
          break nil unless acc.is_a?(Hash)
          acc[seg]
        }

        case value
        when nil, '' then ''
        else              value.to_s
        end
      end
    end
  end
end
