# frozen_string_literal: true

module DDBJRecord
  module Canonicalizer
    # Structural diff of two ALREADY-CANONICAL trees, in time linear in their
    # size.
    #
    # A general array diff aligns two arrays by comparing every element of
    # one with every element of the other; json-diff, which this walker
    # replaced, did so with an N×M similarity matrix, and on a BioSample
    # submission that was quadratic in the sample count (500 samples ~1 s,
    # 2,000 ~12 s, 8,000 ~180 s). It does not have to be that expensive,
    # because every array of a record has a registered mode (§3.1) that
    # already says which elements are the same one:
    #
    # - `keyed`: canonicalisation sorted both sides by the key, so walking the
    #   two sorted runs together pairs them. Elements with equal keys are
    #   paired by position, which under `ties: written` is also what they
    #   mean — the second of two equal aliases before is the second after.
    # - `ordered`: positions are the identity. What an edit leaves alone is a
    #   common prefix and suffix; the elements between are paired by position,
    #   so an inserted element is one `add` and an edited title is a `replace`
    #   of the title, not a `remove` + `add` of the element holding it.
    # - `bag`: an element is its content (§3.1), so a changed element is a
    #   `remove` of the old one and an `add` of the new — never a patch into
    #   one, which the patch verifier rejects.
    #
    # Ops are emitted against the array as it is being mutated, so the walks
    # keep a cursor on the working position: a removal leaves it where it is,
    # an insertion or a kept element advances it.
    module TreeDiffer
      class << self
        # Both sides must already be canonical (`canonicalize(..., for_diff:
        # true)` round-tripped through Oj), because the walks rely on the
        # canonical order.
        def diff(before, after)
          ops = []
          walk(before, after, pointer: '', structural: '', ops:)
          ops
        end

        private

        def walk(before, after, pointer:, structural:, ops:)
          if before.is_a?(Hash) && after.is_a?(Hash)
            walk_hash(before, after, pointer:, structural:, ops:)
          elsif before.is_a?(Array) && after.is_a?(Array)
            walk_array(before, after, pointer:, structural:, ops:)
          elsif before != after
            ops << {'op' => 'replace', 'path' => pointer, 'value' => after}
          end
        end

        def walk_hash(before, after, pointer:, structural:, ops:)
          (before.keys | after.keys).each do |key|
            child        = "#{pointer}/#{escape(key)}"
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

        def walk_array(before, after, pointer:, structural:, ops:)
          rule = PathClassifier.array_rule(structural)

          case rule.fetch('mode')
          when 'keyed'   then walk_keyed(before, after, key: Array(rule['key']), pointer:, structural:, ops:)
          when 'ordered' then walk_run(before, after, cursor: 0, pointer:, structural:, ops:)
          else                walk_bag(before, after, pointer:, ops:)
          end
        end

        # Merge-join two runs that are already sorted by the same key; the
        # elements of one key are a run of their own.
        def walk_keyed(before, after, key:, pointer:, structural:, ops:)
          groups_b = group_by_key(before, key)
          groups_a = group_by_key(after, key)

          (groups_b.keys | groups_a.keys).sort.reduce(0) {|cursor, tuple|
            walk_run(groups_b[tuple] || [], groups_a[tuple] || [], cursor:, pointer:, structural:, ops:)
          }
        end

        # Two runs whose positions are their identity, starting at `cursor`
        # of the working array. Answers the cursor after them.
        def walk_run(before, after, cursor:, pointer:, structural:, ops:)
          prefix = before.zip(after).take_while {|b, a| b == a }.size
          rest   = [before.size, after.size].min - prefix
          suffix = before.last(rest).reverse.zip(after.last(rest).reverse).take_while {|b, a| b == a }.size

          middle_b = before[prefix...(before.size - suffix)]
          middle_a = after[prefix...(after.size - suffix)]
          paired   = [middle_b.size, middle_a.size].min

          cursor += prefix

          middle_b.first(paired).zip(middle_a.first(paired)).each do |before_item, after_item|
            walk(before_item, after_item, pointer: "#{pointer}/#{cursor}", structural: "#{structural}/*", ops:)
            cursor += 1
          end

          middle_b.drop(paired).each do
            ops << {'op' => 'remove', 'path' => "#{pointer}/#{cursor}"}
          end

          middle_a.drop(paired).each do |after_item|
            ops << {'op' => 'add', 'path' => "#{pointer}/#{cursor}", 'value' => after_item}
            cursor += 1
          end

          cursor + suffix
        end

        # Both sides are sorted by content hash, so the elements kept are in
        # the same order on both: removing the ones that went leaves them in
        # place, and the new ones are added where they stand after.
        def walk_bag(before, after, pointer:, ops:)
          unmatched = after.tally

          kept = before.map {|item|
            next false unless unmatched[item].to_i.positive?

            unmatched[item] -= 1
            true
          }

          kept.each_with_index.reverse_each do |keep, index|
            ops << {'op' => 'remove', 'path' => "#{pointer}/#{index}"} unless keep
          end

          remaining = before.select.with_index {|_, index| kept[index] }.tally

          after.each_with_index do |item, index|
            if remaining[item].to_i.positive?
              remaining[item] -= 1
            else
              ops << {'op' => 'add', 'path' => "#{pointer}/#{index}", 'value' => item}
            end
          end
        end

        def group_by_key(items, key)
          items.group_by {|item| key.map { ArraySorter.key_component(item, it) } }
        end

        # RFC 6901: `~` becomes `~0`, `/` becomes `~1`.
        def escape(token) = token.to_s.gsub('~', '~0').gsub('/', '~1')
      end
    end
  end
end
