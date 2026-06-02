# frozen_string_literal: true

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

      module_function

      def array_mode(pointer)
        rule = best_match(pointer, Registry.arrays) || ARRAY_DEFAULT
        rule.fetch('mode')
      end

      def array_rule(pointer)
        best_match(pointer, Registry.arrays) || ARRAY_DEFAULT
      end

      def string_class(pointer)
        rule = best_match(pointer, Registry.strings.fetch('paths'))
        rule || Registry.strings['default'] || STRING_DEFAULT
      end

      def volatile?(pointer)
        Registry.volatile_paths.any? {|pattern| match?(pattern, pointer) }
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
