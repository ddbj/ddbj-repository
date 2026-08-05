# frozen_string_literal: true

module DDBJRecord
  module Canonicalizer
    # Structural diff of two ALREADY-CANONICAL trees.
    #
    # `json-diff` aligns two arrays by building an N×M similarity matrix
    # (`before.map { after.map { similarity(...) } }`) and sorting it. On a
    # BioSample submission that is quadratic in the sample count: 500
    # samples diff in ~1 s, 2,000 in ~12 s, 8,000 in ~180 s. The corpus has
    # submissions an order of magnitude larger than that.
    #
    # It does not have to be that expensive. A `keyed` array carries a
    # registry-declared identity (`/samples` is keyed on `alias`), and
    # canonicalisation has already sorted BOTH sides by that key — so the
    # alignment json-diff is searching for is already known. Walking the
    # two sorted runs together is linear.
    #
    # So: this walker handles objects and keyed arrays itself, and hands
    # anything else — ordered arrays, bags, scalars — to json-diff on that
    # subtree alone, where the arrays are small by construction.
    module TreeDiffer
      class << self
        # Both sides must already be canonical (`canonicalize(..., for_diff:
        # true)` round-tripped through Oj), because keyed matching relies on
        # the canonical sort order.
        def diff(before, after)
          ops = []
          walk(before, after, pointer: '', structural: '', ops:)
          ops
        end

        private

        def walk(before, after, pointer:, structural:, ops:)
          if before.is_a?(Hash) && after.is_a?(Hash)
            walk_hash(before, after, pointer:, structural:, ops:)
          elsif before.is_a?(Array) && after.is_a?(Array) && (key = keyed_key(structural))
            walk_keyed(before, after, key:, pointer:, structural:, ops:)
          elsif before == after
            nil
          else
            ops.concat(delegate(before, after, pointer:))
          end
        end

        def walk_hash(before, after, pointer:, structural:, ops:)
          (before.keys | after.keys).each do |key|
            child      = "#{pointer}/#{escape(key)}"
            child_struct = "#{structural}/#{escape(key)}"

            if !after.key?(key)
              ops << {'op' => 'remove', 'path' => child}
            elsif !before.key?(key)
              ops << {'op' => 'add', 'path' => child, 'value' => after[key]}
            else
              walk(before[key], after[key], pointer: child, structural: child_struct, ops:)
            end
          end
        end

        # Merge-join two runs that are already sorted by the same key.
        #
        # Ops are emitted against the array as it is being mutated, so
        # `cursor` tracks the working position: a removal shifts the tail
        # left and leaves the cursor where it is, an insertion advances it.
        def walk_keyed(before, after, key:, pointer:, structural:, ops:)
          groups_b = group_by_key(before, key)
          groups_a = group_by_key(after, key)

          cursor = 0

          (groups_b.keys | groups_a.keys).sort.each do |tuple|
            old = groups_b[tuple] || []
            new = groups_a[tuple] || []

            # Equal-key elements are further ordered by content hash, so
            # pairing them positionally is arbitrary but correct; in
            # practice a key identifies at most one element.
            old.zip(new).each do |before_item, after_item|
              if after_item.nil?
                ops << {'op' => 'remove', 'path' => "#{pointer}/#{cursor}"}
              else
                walk(before_item, after_item,
                     pointer: "#{pointer}/#{cursor}", structural: "#{structural}/*", ops:)
                cursor += 1
              end
            end

            new.drop(old.size).each do |after_item|
              ops << {'op' => 'add', 'path' => "#{pointer}/#{cursor}", 'value' => after_item}
              cursor += 1
            end
          end
        end

        def group_by_key(items, key)
          items.group_by {|item| key.map { ArraySorter.key_component(item, it) } }
        end

        # nil unless this pointer is registered `{mode: keyed}`; the key
        # list comes from the same registry entry ArraySorter sorts by, so
        # the two cannot drift.
        def keyed_key(structural)
          rule = PathClassifier.array_rule(structural)
          return nil unless rule.is_a?(Hash) && rule['mode'] == 'keyed'

          Array(rule['key'])
        end

        # Everything this walker does not special-case. The subtree is
        # small by construction — the large arrays in a DDBJ Record are the
        # keyed ones — so json-diff's alignment cost is bounded here.
        def delegate(before, after, pointer:)
          JsonDiff.diff(before, after, moves: false, include_was: false).filter_map {|op|
            next nil unless %w[add remove replace].include?(op['op'])

            out = {'op' => op['op'], 'path' => "#{pointer}#{op['path']}"}
            out['value'] = op['value'] if op.key?('value')
            out
          }
        end

        # RFC 6901: `~` becomes `~0`, `/` becomes `~1`.
        def escape(token) = token.to_s.gsub('~', '~0').gsub('/', '~1')
      end
    end
  end
end
