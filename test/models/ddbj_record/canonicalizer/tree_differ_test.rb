require 'test_helper'

module DDBJRecord::Canonicalizer; end

# TreeDiffer replaces json-diff's N×M array alignment for keyed arrays.
# The behaviour that matters is not the op shape but the round trip:
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

  # Nested structures still reach json-diff; the walker must prefix its
  # paths correctly on the way back out.
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

  # json-diff aligned arrays with an N×M similarity matrix, so this shape
  # took ~180 s at 8,000 elements. The assertion is correctness; the
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
end
