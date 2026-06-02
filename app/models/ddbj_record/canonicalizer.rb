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
      # numeric indices into `keyed` / `bag` arrays match. `moves: false`
      # blocks `move` ops; the result is post-filtered to add / remove /
      # replace only.
      def diff(a, b)
        canon_a  = parse_canonical(a)
        canon_b  = parse_canonical(b)

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

      # Apply a patch atomically — work on a deep dup and discard on raise.
      def apply(base, patch)
        canon_base  = parse_canonical(base)
        patch.each {|op| reject_bag_descent!(op) }

        working = Marshal.load(Marshal.dump(canon_base))
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

      def parse_canonical(value)
        bytes = canonicalize(value)
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

      def reject_bag_descent!(op)
        %w[path from].each do |field|
          path = op[field] or next

          segments = path.split('/').drop(1)
          prefix   = +''
          segments.each_with_index do |seg, idx|
            prefix << '/' << seg
            next unless PathClassifier.array_mode(prefix) == 'bag'

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
