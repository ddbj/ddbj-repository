# frozen_string_literal: true

require 'digest'

module DDBJRecord
  module Canonicalizer
    # Recursive bottom-up transformer. Each visit returns a `Result`:
    #
    #   tree  — the post-normalisation Ruby value (Hash / Array / String /
    #           Integer / Float / true / false)
    #   bytes — canonical UTF-8 JCS bytes for that subtree
    #   sha   — `Digest::SHA256.hexdigest(bytes)` (LAZY)
    #
    # Performance contract (see canonical-json.md §3.1):
    #
    # - Container bytes (`{...}` / `[...]`) are COMPOSED from children's
    #   already-computed bytes rather than re-serialised at every level via
    #   `JcsAdapter.dump(subtree)`. Total bytes work is therefore O(n) in
    #   the tree's total size, not O(D × n) where D is depth.
    #
    # - SHA is computed lazily on first access. ArraySorter only needs
    #   `.sha` for bag (`sort_by(&:sha)`) and keyed (tie-break) elements;
    #   hash children and ordered-array elements never pay for it.
    #
    # - Pointers passed down to children use the STRUCTURAL form: array
    #   indices are emitted as `*` rather than the literal integer. The
    #   PathClassifier registry uses `*` wildcards for variable-index
    #   segments and contains no concrete-index rules (verified across
    #   arrays / strings / floats / volatile_paths), so this is
    #   observationally equivalent to literal-index pointers for rule
    #   resolution while collapsing the PathClassifier memo to ~16
    #   steady-state entries.
    #
    # The composite effect of these three is ~8× wall clock on a 20K-sample
    # BS record (SSUB004153, 7 MB canonical: 21 s → 2.6 s).
    module Normalizer
      class Result
        attr_reader :tree, :bytes

        def initialize(tree:, bytes:)
          @tree  = tree
          @bytes = bytes
        end

        def sha
          @sha ||= Digest::SHA256.hexdigest(@bytes)
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

          [key, child_result]
        }

        sorted = sort_by_canonical_key(entries)
        tree   = sorted.to_h {|k, r| [k, r.tree] }
        bytes  = compose_hash_bytes(sorted)

        Result.new(tree: tree, bytes: bytes)
      end

      # @api private
      def visit_array(array, pointer:)
        # Structural pointer: pass `*` once for the whole array rather
        # than `/0`, `/1`, ... per element. See the module-level comment.
        child_pointer = "#{pointer}/*"
        child_results = array.map {|element| visit(element, pointer: child_pointer) }

        sorted = ArraySorter.sort(child_results, pointer:)
        tree   = sorted.map(&:tree)
        bytes  = compose_array_bytes(sorted)

        Result.new(tree: tree, bytes: bytes)
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
        Result.new(tree: value, bytes: JcsAdapter.dump(value))
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

      # JSON Pointer (RFC 6901) escapes `~` → `~0` and `/` → `~1`. DDBJ
      # Record keys are typed identifiers (`[a-z][a-z0-9_]*` style) that
      # never contain either, so 99%+ of calls are no-ops. Fast-path the
      # common case to skip the two gsubs entirely — measured ~10% wall
      # clock on SSUB004153 because escape_pointer fires once per hash
      # entry visited (320K calls on a 20K-sample BS record).
      # @api private
      def escape_pointer(seg)
        return seg unless seg.include?('~') || seg.include?('/')

        seg.gsub('~', '~0').gsub('/', '~1')
      end

      # RFC 8785 §3.2.3 mandates that object keys sort by UTF-16 code
      # units. For the ASCII-only key namespace the DDBJ Record schema
      # uses, bytewise String#<=> matches that ordering exactly (each
      # ASCII char encodes to one byte in UTF-8 and one code unit in
      # UTF-16, with the same numeric value). Skip the explicit UTF-16
      # encode in the all-ASCII case (~100% of real records), fall back
      # to it only when a non-BMP / non-ASCII key shows up — the
      # non_bmp_key_test pins this contract.
      # @api private
      def sort_by_canonical_key(entries)
        return entries if entries.size < 2

        if entries.all? {|k, _| k.ascii_only? }
          entries.sort_by(&:first)
        else
          entries.sort_by {|k, _| k.encode(Encoding::UTF_16BE) }
        end
      end

      # @api private
      def compose_hash_bytes(sorted_entries)
        parts = sorted_entries.map {|k, r| "#{JcsAdapter.dump(k)}:#{r.bytes}" }
        ('{' + parts.join(',') + '}').force_encoding(Encoding::UTF_8)
      end

      # @api private
      def compose_array_bytes(sorted_results)
        ('[' + sorted_results.map(&:bytes).join(',') + ']').force_encoding(Encoding::UTF_8)
      end
    end
  end
end
