# frozen_string_literal: true

require 'concurrent/map'

module DDBJRecord
  module Canonicalizer
    # Resolve a JSON Pointer (as a String, e.g. `/samples/3/attributes/0`)
    # against the array-modes / strings / volatile_paths registry. Patterns
    # use two wildcards:
    #
    #   `*`  — exactly one path segment (any value)
    #   `**` — zero or more segments
    #
    # Concrete (no-wildcard) matches always win over wildcard matches; among
    # wildcard matches, longer patterns and earlier `**` positions win. The
    # precedence rules are deterministic so the registry can list specific
    # paths alongside `/**/attributes`-style fallbacks without surprises.
    module PathClassifier
      ARRAY_DEFAULT  = {'mode' => 'bag'}.freeze
      STRING_DEFAULT = 'multi_line'

      # Collapse literal array-index segments (`/0`, `/1`, …) to the
      # structural `*` wildcard before cache lookup AND before rule
      # resolution. Structural pointers bound the cache to the number of
      # distinct schema shapes (~16 entries) regardless of whether the
      # caller (Normalizer / VolatileStripper / Canonicalizer's
      # bag-descent guard) passes literal or structural pointers.
      #
      # Normalisation is only safe when the underlying registry table
      # contains NO concrete-numeric patterns (e.g. a stubbed
      # `volatile_paths = ['/items/0']` would resolve differently for
      # `/items/0` vs `/items/1`). We check each registry on first
      # access and memoise the verdict, falling back to literal-pointer
      # lookup for that table when concrete-index rules are present.
      # The flag plus the caches are cleared by `reset!` (in turn called
      # from `Registry.reload!`), so test stubs and runtime rule
      # changes do not leak across boundaries.
      STRUCTURAL_INDEX_REGEXP        = %r{/\d+(?=/|\z)}.freeze
      CONCRETE_INDEX_SEGMENT_REGEXP  = /\A\d+\z/.freeze

      # Concurrent::Map for atomic `compute_if_absent`. The registry is
      # static so cached values are deterministic functions of the
      # structural pointer, but plain-Hash `||=` would let two cold-start
      # threads race and both compute. compute_if_absent serialises the
      # first-touch and lets every other reader pick up the result.
      @array_rule_cache    = Concurrent::Map.new
      @string_class_cache  = Concurrent::Map.new
      @volatile_cache      = Concurrent::Map.new
      @float_allowed_cache = Concurrent::Map.new

      class << self
        attr_reader :array_rule_cache, :string_class_cache, :volatile_cache, :float_allowed_cache

        # Clear every cache and the structural-normalisation safety flags.
        # Hooked into Registry.reload! so a stub / hot-reload of the
        # rules table doesn't leak stale resolutions into post-reload
        # calls.
        def reset!
          array_rule_cache.clear
          string_class_cache.clear
          volatile_cache.clear
          float_allowed_cache.clear

          @normalize_arrays   = nil
          @normalize_strings  = nil
          @normalize_volatile = nil
          @normalize_floats   = nil
        end
      end

      module_function

      def array_mode(pointer)
        array_rule(pointer).fetch('mode')
      end

      def array_rule(pointer)
        key = PathClassifier.normalize_arrays? ? structural_key(pointer) : pointer

        PathClassifier.array_rule_cache.compute_if_absent(key) {
          best_match(key, Registry.arrays) || ARRAY_DEFAULT
        }
      end

      def string_class(pointer)
        key = PathClassifier.normalize_strings? ? structural_key(pointer) : pointer

        PathClassifier.string_class_cache.compute_if_absent(key) {
          best_match(key, Registry.strings.fetch('paths')) || Registry.strings['default'] || STRING_DEFAULT
        }
      end

      def volatile?(pointer)
        key = PathClassifier.normalize_volatile? ? structural_key(pointer) : pointer

        PathClassifier.volatile_cache.compute_if_absent(key) {
          Registry.volatile_paths.any? {|pattern| match?(pattern, key) }
        }
      end

      def float_allowed?(pointer)
        key = PathClassifier.normalize_floats? ? structural_key(pointer) : pointer

        PathClassifier.float_allowed_cache.compute_if_absent(key) {
          Registry.floats.any? {|pattern| match?(pattern, key) }
        }
      end

      # Per-table memoised flag answering "is structural normalisation
      # safe for THIS registry table?". Each accessor returns true when
      # the registered patterns are wildcard-only (no concrete numeric
      # segments) — which is the case for the production array-modes
      # registry today. A test stub or YAML edit that introduces a
      # `/items/0`-style pattern flips the flag to false for that table,
      # so the cache for that table falls back to literal-pointer keys
      # and the concrete-index rule keeps its targeted behaviour.
      class << self
        def normalize_arrays?
          @normalize_arrays = wildcard_only?(Registry.arrays.keys) if @normalize_arrays.nil?
          @normalize_arrays
        end

        def normalize_strings?
          @normalize_strings = wildcard_only?(Registry.strings.fetch('paths').keys) if @normalize_strings.nil?
          @normalize_strings
        end

        def normalize_volatile?
          @normalize_volatile = wildcard_only?(Registry.volatile_paths) if @normalize_volatile.nil?
          @normalize_volatile
        end

        def normalize_floats?
          @normalize_floats = wildcard_only?(Registry.floats) if @normalize_floats.nil?
          @normalize_floats
        end

        private

        def wildcard_only?(patterns)
          patterns.none? {|pattern|
            pattern.split('/').drop(1).any? {|seg| seg.match?(CONCRETE_INDEX_SEGMENT_REGEXP) }
          }
        end
      end

      # Cheap gsub-or-passthrough: skips allocation when the pointer is
      # already in structural form (Normalizer's path) and only rewrites
      # when literal indices are present (VolatileStripper /
      # reject_bag_descent! paths).
      # @api private
      def structural_key(pointer)
        if pointer.match?(STRUCTURAL_INDEX_REGEXP)
          pointer.gsub(STRUCTURAL_INDEX_REGEXP, '/*')
        else
          pointer
        end
      end

      # @api private
      def best_match(pointer, table)
        candidates = table.filter_map {|pattern, value|
          [score(pattern, pointer), pattern.length, value] if match?(pattern, pointer)
        }

        return nil if candidates.empty?

        candidates.max_by {|score, length, _| [score, length] }.last
      end

      # Returns an integer rank; higher is more specific.
      # @api private
      def score(pattern, _pointer)
        segs = pattern.split('/').drop(1)

        return 1_000_000 if segs.none? {|s| s == '*' || s == '**' }

        wildcards   = segs.count {|s| s == '*' }
        deepstar    = segs.count {|s| s == '**' }
        first_star  = segs.index {|s| s == '*' || s == '**' } || segs.length

        (first_star * 1_000) - (wildcards * 10) - (deepstar * 100)
      end

      # Glob match against a JSON Pointer string. Both sides are pre-split on
      # `/` so the empty leading segment (everything before the first `/`)
      # falls out naturally.
      # @api private
      def match?(pattern, pointer)
        glob   = pattern.split('/').drop(1)
        target = pointer.split('/').drop(1)
        match_segments?(glob, target)
      end

      def match_segments?(glob, target)
        return target.empty? if glob.empty?

        head, *rest = glob

        case head
        when '**'
          return true if rest.empty?

          (0..target.length).any? {|i| match_segments?(rest, target[i..]) }
        when '*'
          return false if target.empty?

          match_segments?(rest, target[1..])
        else
          return false if target.empty? || target.first != head

          match_segments?(rest, target[1..])
        end
      end
    end
  end
end
