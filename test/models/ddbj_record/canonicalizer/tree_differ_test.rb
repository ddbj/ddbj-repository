require 'test_helper'

module DDBJRecord::Canonicalizer; end

# TreeDiffer pairs array elements by each array's registered mode instead
# of aligning every element with every other. The behaviour that matters
# most is not the op shape but the round trip:
# applying what it emits must reproduce the target exactly, because that
# is the property the whole patch chain rests on.
class DDBJRecord::Canonicalizer::TreeDifferTest < ActiveSupport::TestCase
  C = DDBJRecord::Canonicalizer

  def round_trip(before, after)
    canon_before = C.canonical_tree(before)
    canon_after  = C.canonical_tree(after)

    C.apply(canon_before, C.diff(canon_before, canon_after))
  end

  def samples(*aliases) = {'samples' => aliases.map { {'alias' => it} }}

  test 'an unchanged tree produces no ops' do
    tree = samples('a', 'b', 'c')

    assert_empty C.diff(tree, tree)
  end

  test 'a single edit produces a single op' do
    before = samples('a', 'b')
    after  = {'samples' => [{'alias' => 'a'}, {'alias' => 'b', 'title' => 'B'}]}

    ops = C.diff(before, after)

    assert_equal [{'op' => 'add', 'path' => '/samples/1/title', 'value' => 'B'}], ops
  end

  test 'inserting into the middle of a keyed array' do
    assert_equal C.canonical_tree(samples('a', 'b', 'c')),
                 round_trip(samples('a', 'c'), samples('a', 'b', 'c'))
  end

  test 'removing from the middle of a keyed array' do
    assert_equal C.canonical_tree(samples('a', 'c')),
                 round_trip(samples('a', 'b', 'c'), samples('a', 'c'))
  end

  test 'several removals in one patch keep their indices straight' do
    assert_equal C.canonical_tree(samples('c')),
                 round_trip(samples('a', 'b', 'c', 'd', 'e'), samples('c'))
  end

  test 'interleaved adds and removes' do
    assert_equal C.canonical_tree(samples('a', 'c', 'e')),
                 round_trip(samples('b', 'c', 'd'), samples('a', 'c', 'e'))
  end

  test 'input order does not matter, only key order' do
    assert_equal C.canonical_tree(samples('a', 'b', 'c')),
                 round_trip(samples('c', 'a'), samples('c', 'b', 'a'))
  end

  test 'an emptied keyed array' do
    assert_equal C.canonical_tree({'samples' => []}),
                 round_trip(samples('a', 'b'), {'samples' => []})
  end

  test 'a keyed array appearing from nothing' do
    assert_equal C.canonical_tree(samples('a', 'b')), round_trip({}, samples('a', 'b'))
  end

  # The walker must prefix its paths correctly on the way back out of a
  # nested array.
  test 'edits inside a sample attribute bag round-trip' do
    before = {'samples' => [{'alias' => 'a', 'attributes' => [{'name' => 'depth', 'value' => '1'}]}]}
    after  = {'samples' => [{'alias' => 'a', 'attributes' => [{'name' => 'depth', 'value' => '2'}]}]}

    assert_equal C.canonical_tree(after), round_trip(before, after)
  end

  test 'object edits outside any array round-trip' do
    before = {'submission' => {'hold_date' => '2026-01-01', 'comments' => 'x'}}
    after  = {'submission' => {'hold_date' => '2027-01-01'}}

    assert_equal C.canonical_tree(after), round_trip(before, after)
  end

  # Aligned N×M (json-diff, which this walker replaced), this shape took
  # ~180 s at 8,000 elements. The assertion is correctness; the
  # generous bound is only here to fail loudly if the quadratic path
  # returns.
  test 'a large keyed array diffs in linear time' do
    before = {'samples' => (1..4_000).map { {'alias' => "s#{it}", 'title' => 'x' * 40} }}
    after  = {'samples' => (1..4_000).map { {'alias' => "s#{it}", 'title' => 'x' * 40, 'accession' => "SAMD#{it}"} }}

    canon_before = C.canonical_tree(before)
    canon_after  = C.canonical_tree(after)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ops     = C.diff(canon_before, canon_after)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_equal 4_000,       ops.size
    assert_equal canon_after, C.apply(canon_before, ops)
    assert_operator elapsed, :<, 20, 'diff of 4,000 keyed elements should not be quadratic'
  end

  test 'an element inserted before equal aliases is one add' do
    before = {'experiments' => [{'alias' => 'x', 'title' => '1'}, {'alias' => 'x', 'title' => '2'}]}
    after  = {'experiments' => [{'alias' => 'x', 'title' => '0'}, {'alias' => 'x', 'title' => '1'}, {'alias' => 'x', 'title' => '2'}]}

    ops = C.diff(before, after)

    assert_equal [{'op' => 'add', 'path' => '/experiments/0', 'value' => {'alias' => 'x', 'title' => '0'}}], ops
    assert_equal C.canonical_tree(after), round_trip(before, after)
  end

  test 'the first of equal aliases removed is one remove' do
    before = {'experiments' => [{'alias' => 'x', 'title' => '1'}, {'alias' => 'x', 'title' => '2'}]}
    after  = {'experiments' => [{'alias' => 'x', 'title' => '2'}]}

    assert_equal [{'op' => 'remove', 'path' => '/experiments/0'}], C.diff(before, after)
  end

  test 'an element inserted at the front of an ordered array is one add' do
    before = {'sequences' => {'entries' => (1..2_000).map { {'alias' => "c#{it}", 'sequence' => 'acgt'} }}}
    after  = {'sequences' => {'entries' => [{'alias' => 'c0', 'sequence' => 'acgt'}, *before.dig('sequences', 'entries')]}}

    ops = C.diff(before, after)

    assert_equal [{'op' => 'add', 'path' => '/sequences/entries/0', 'value' => {'alias' => 'c0', 'sequence' => 'acgt'}}], ops
  end

  test 'a changed bag element is removed and added, never patched into' do
    before = {'sequences' => {'structured_comments' => [{'tagset_id' => 'A', 'fields' => {'x' => '1'}}]}}
    after  = {'sequences' => {'structured_comments' => [{'tagset_id' => 'A', 'fields' => {'x' => '2'}}]}}

    ops = C.diff(before, after)

    assert_equal %w[remove add], ops.map { it['op'] }
    assert_equal C.canonical_tree(after), round_trip(before, after)
  end

  # Lists of each mode, with repeated keys and repeated elements, changed at
  # random: whatever the walks pair, applying their ops has to give the target.
  test 'random edits of keyed, ordered and bag lists round-trip' do
    random = Random.new(20_260_927)

    element = -> { {'alias' => %w[a b c].sample(random:), 'title' => %w[t u].sample(random:)} }
    record  = -> {
      {
        'experiments' => Array.new(random.rand(0..6)) { element.() },
        'sequences'   => {
          'entries'             => Array.new(random.rand(0..6)) { {'alias' => element.()['alias'], 'sequence' => %w[ac gt].sample(random:)} },
          'structured_comments' => Array.new(random.rand(0..4)) { {'tagset_id' => %w[A B].sample(random:)} }
        }
      }
    }

    300.times do
      before = record.()
      after  = record.()

      assert_equal C.canonical_tree(after), round_trip(before, after), "#{before.inspect} -> #{after.inspect}"
    end
  end
end
