# frozen_string_literal: true

require 'digest'
require 'hana'
require 'json-diff'

# DDBJ Record JSON canonicalization. See tmp/data-migration/canonical-json.md.
# The wire-format identifier (VERSION) stays `ddbj-canon/v1` per spec; the
# Ruby namespace is rooted under DDBJRecord because canonicalization is a
# property of the DDBJ Record format, not of any organisation.
module DDBJRecord
  module Canonicalizer
    VERSION = 'ddbj-canon/v1'.freeze

    class Error < StandardError; end

    class ControlCharacterError     < Error; end
    class SequenceAlphabetError     < Error; end
    class FloatNotAllowedError      < Error; end
    class IntegerOutOfRangeError    < Error; end
    class OrderedEmptyElementError  < Error; end
    class BagPatchPathError         < Error; end
    class IdempotenceViolationError < Error; end
    class UnsupportedValueError     < Error; end

    # JSON Patch ops that mutate the document. `test` is read-only and cannot
    # shift bag indices, so it is exempt from the bag-descent guard.
    MUTATING_OPS = %w[add remove replace move copy].freeze

    class << self
      # Canonical UTF-8 bytes per ddbj-canon/v1. Pass `for_diff: true` to
      # strip volatile sub-trees (provenance, server-assigned accessions,
      # etc.) before normalisation so the resulting hash represents the
      # curator-meaningful content only.
      def canonicalize(value, for_diff: false)
        Normalizer.transform(prepare(value, for_diff:)).bytes
      end

      # Lowercase hex SHA-256 of the canonical bytes. Same kwargs as
      # `canonicalize`.
      def sha256(value, for_diff: false)
        Normalizer.transform(prepare(value, for_diff:)).sha
      end

      # Strip volatile sub-trees and return a plain Ruby hash. The result is
      # still pre-canonical (no key sort, no NFC); pass it back into
      # `canonicalize` to get bytes.
      def strip_volatile(value)
        VolatileStripper.strip(coerce_for_strip(value))
      end

      # `json-diff` based differ. Both sides are canonicalised first so
      # numeric indices into `keyed` / `bag` arrays match. Volatile sub-trees
      # are stripped (canonical-json.md §4.2: "chain replay uses True on
      # both sides"). `moves: false` blocks `move` ops; the result is
      # post-filtered to add / remove / replace only.
      def diff(a, b)
        canon_a = parse_canonical(a, for_diff: true)
        canon_b = parse_canonical(b, for_diff: true)

        ops = JsonDiff.diff(canon_a, canon_b, moves: false, include_was: false)
        ops.filter_map {|op|
          next nil unless %w[add remove replace].include?(op['op'])
          reject_bag_descent!(op)
          {'op' => op['op'], 'path' => op['path']}.then {|out|
            out['value'] = op['value'] if op.key?('value')
            out
          }
        }
      end

      # Apply a patch atomically. `base` is deep-copied so caller state is
      # never observed mid-mutation; on raise the working copy is discarded.
      # NOTE: `apply` is a pure RFC 6902 operation — it does NOT canonicalise
      # `base` first. Callers that need a canonical output must pass
      # already-canonical bytes (`Oj.load(canonicalize(base))`).
      def apply(base, patch)
        patch.each {|op| reject_bag_descent!(op) }

        working = coerce_for_strip(base).deep_dup
        Hana::Patch.new(patch).apply(working)
      rescue Hana::Patch::Exception, Hana::Patch::FailedTestException, Hana::Patch::OutOfBoundsException => e
        raise Error, "patch apply failed: #{e.class}: #{e.message}"
      end

      # Re-canonicalise a patch document. Op keys sort; each `value` is
      # canonicalised in place under the post-patch pointer.
      def canonicalize_patch(patch)
        normalised = patch.map {|op|
          out = {'op' => op['op'].to_s, 'path' => op['path'].to_s}
          out['from']  = op['from'].to_s if op.key?('from')
          out['value'] = Normalizer.transform(op['value'], pointer: op['path'].to_s).tree if op.key?('value')
          out
        }

        normalised.map {|op| JcsAdapter.dump(op) }.then {|lines|
          ('[' + lines.join(',') + ']').force_encoding(Encoding::UTF_8)
        }
      end

      private

      def prepare(value, for_diff:)
        return strip_volatile(value) if for_diff

        coerce_for_strip(value)
      end

      def parse_canonical(value, for_diff: false)
        bytes = canonicalize(value, for_diff:)
        Oj.load(bytes, mode: :strict)
      end

      def coerce_for_strip(value)
        case value
        when Data  then coerce_for_strip(value.to_h)
        when Hash  then value.each_with_object({}) {|(k, v), h| h[k.to_s] = coerce_for_strip(v) }
        when Array then value.map {|v| coerce_for_strip(v) }
        else            value
        end
      end

      # Mutating ops into a bag array's interior are forbidden by
      # canonical-json.md §3.1 — bags are content-addressed, so an
      # element-level edit would re-sort the whole array. `test` is
      # read-only and exempt.
      #
      # The guard uses `PathClassifier.explicit_bag?` (NOT `array_mode`):
      # `array_mode` returns the default `'bag'` for ANY unregistered
      # pointer, including OBJECT prefixes like `/submission` or
      # `/project`. Walking those with `array_mode == 'bag'` would
      # false-positive on every patch whose path passes through an
      # unregistered hash key. `explicit_bag?` only returns true when
      # the path is registered as `{mode: bag}` in array-modes.yml.
      def reject_bag_descent!(op)
        return unless MUTATING_OPS.include?(op['op'])

        %w[path from].each do |field|
          path = op[field] or next

          # `split('/', -1)` preserves trailing empty segments — an empty
          # string IS a valid RFC 6901 reference token, so dropping it would
          # let `/experiments/0/` sneak through the guard.
          segments = path.split('/', -1).drop(1)
          prefix   = +''
          segments.each_with_index do |seg, idx|
            prefix << '/' << seg
            next unless PathClassifier.explicit_bag?(prefix)

            tail = segments[(idx + 1)..]
            next if tail.length <= 1 # bag/<idx> is fine; bag/<idx>/anything is not

            raise BagPatchPathError,
                  "patch path #{path.inspect} descends into bag array at #{prefix}; " \
                  'bags require whole-element add/remove'
          end
        end
      end
    end
  end
end
