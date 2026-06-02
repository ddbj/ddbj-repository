# frozen_string_literal: true

require 'digest'

module DDBJRecord
  module Canonicalizer
    # Recursive bottom-up transformer. Each visit returns a `Result`:
    #
    #   tree  — the post-normalisation Ruby value (Hash / Array / String /
    #           Integer / Float / true / false)
    #   bytes — `JcsAdapter.dump(tree)` for that subtree; canonical UTF-8
    #   sha   — `Digest::SHA256.hexdigest(bytes)`
    #
    # Holding `bytes` alongside `tree` lets ArraySorter compare keyed-tuple
    # ties and rank bag elements without re-canonicalising. The whole
    # document is canonicalised exactly once per pass.
    module Normalizer
      Result = Data.define(:tree, :bytes, :sha) do
        def self.from_tree(tree)
          bytes = JcsAdapter.dump(tree)
          new(tree:, bytes:, sha: Digest::SHA256.hexdigest(bytes))
        end
      end

      module_function

      # Public entry: walks `value` and returns the top-level Result. The
      # caller pulls `.bytes` for the canonical JSON or `.sha` for the
      # content hash.
      def transform(value, pointer: '')
        visit(coerce(value), pointer:)
      end

      # @api private
      def visit(value, pointer:)
        case value
        when Hash         then visit_hash(value, pointer:)
        when Array        then visit_array(value, pointer:)
        when String       then visit_string(value, pointer:)
        when Integer      then leaf(NumberGuard.check!(value, pointer:))
        when Float        then leaf(NumberGuard.check!(value, pointer:, allow_float: PathClassifier.float_allowed?(pointer)))
        when TrueClass, FalseClass then leaf(value)
        when nil          then leaf(nil)
        else
          raise UnsupportedValueError, "unsupported #{value.class} at #{pointer}"
        end
      end

      # @api private
      def visit_hash(hash, pointer:)
        entries = hash.filter_map {|raw_key, raw_value|
          key = raw_key.to_s
          next nil if raw_value.nil?

          child_pointer = "#{pointer}/#{escape_pointer(key)}"
          child_result  = visit(raw_value, pointer: child_pointer)

          next nil if EmptyDropper.empty?(child_result.tree)

          [key, child_result.tree]
        }

        tree = entries.to_h
        Result.from_tree(tree)
      end

      # @api private
      def visit_array(array, pointer:)
        child_results = array.each_with_index.map {|element, idx|
          visit(element, pointer: "#{pointer}/#{idx}")
        }

        sorted = ArraySorter.sort(child_results, pointer:)
        tree   = sorted.map(&:tree)

        Result.from_tree(tree)
      end

      # @api private
      def visit_string(string, pointer:)
        klass = PathClassifier.string_class(pointer)

        normalised = if klass == 'sequence'
                       SequenceCodec.normalize(string)
                     else
                       StringNormalizer.normalize(string, klass)
                     end

        leaf(normalised)
      end

      # @api private
      def leaf(value)
        Result.from_tree(value)
      end

      # Accept either a plain Hash/Array tree or a v3 Data instance. Data
      # instances expose their members via `to_h` recursively, so we just
      # convert top-down once and let `visit` handle the rest.
      # @api private
      def coerce(value)
        case value
        when Data  then coerce(value.to_h)
        when Hash  then value.transform_values {|v| coerce(v) }
        when Array then value.map {|v| coerce(v) }
        else            value
        end
      end

      # RFC 6901 §4 escape: `~` → `~0`, `/` → `~1`. Order matters.
      # @api private
      def escape_pointer(seg)
        seg.gsub('~', '~0').gsub('/', '~1')
      end
    end
  end
end
