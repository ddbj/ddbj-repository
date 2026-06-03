require 'test_helper'

# Pins the cache-growth invariants on PathClassifier:
#
# - Cache key is always the STRUCTURAL form (literal indices collapsed to
#   `*`), regardless of caller convention. Without this, callers that pass
#   literal-index pointers (VolatileStripper, Canonicalizer's bag-descent
#   guard) would grow the caches without bound on the Puma worker
#   lifetime — confirmed code-review finding on the perf rewrite.
#
# - reset! actually clears all four caches, and is hooked into
#   Registry.reload! so stubs / hot-reloads can't leak stale resolutions.
class DDBJRecord::Canonicalizer::PathClassifierCacheTest < ActiveSupport::TestCase
  PC = DDBJRecord::Canonicalizer::PathClassifier

  setup do
    PC.reset!
  end

  test 'literal-index pointers collapse to a single cache entry under the structural key' do
    1000.times {|i| PC.array_rule("/samples/#{i}") }

    assert_equal 1, PC.array_rule_cache.size,
                 'every literal-index pointer should hash to the same structural key'
    assert PC.array_rule_cache.key?('/samples/*')
  end

  test 'volatile? collapses literal-index pointers the same way' do
    1000.times {|i| PC.volatile?("/samples/#{i}/attributes/#{i % 3}") }

    assert_equal 1, PC.volatile_cache.size,
                 'volatile_cache must not grow with array length'
    assert PC.volatile_cache.key?('/samples/*/attributes/*')
  end

  test 'string_class and float_allowed? collapse literal indices too' do
    100.times {|i| PC.string_class("/sequences/entries/#{i}/sequence") }
    100.times {|i| PC.float_allowed?("/project/grants/#{i}/amount") }

    assert_equal 1, PC.string_class_cache.size
    assert_equal 1, PC.float_allowed_cache.size
  end

  test 'reset! clears every cache' do
    PC.array_rule('/samples/0')
    PC.string_class('/sequences/entries/0/sequence')
    PC.volatile?('/provenance')
    PC.float_allowed?('/project/grants/0/amount')

    assert_operator PC.array_rule_cache.size,    :>, 0
    assert_operator PC.string_class_cache.size,  :>, 0
    assert_operator PC.volatile_cache.size,      :>, 0
    assert_operator PC.float_allowed_cache.size, :>, 0

    PC.reset!

    assert_equal 0, PC.array_rule_cache.size
    assert_equal 0, PC.string_class_cache.size
    assert_equal 0, PC.volatile_cache.size
    assert_equal 0, PC.float_allowed_cache.size
  end

  test 'Registry.reload! resets PathClassifier caches as a side effect' do
    PC.array_rule('/samples/0')
    assert_operator PC.array_rule_cache.size, :>, 0

    DDBJRecord::Canonicalizer::Registry.reload!

    assert_equal 0, PC.array_rule_cache.size,
                 'Registry.reload! must invalidate PathClassifier caches so post-reload calls do not see stale resolutions'
  end

  test 'structural and literal pointers resolve to the same rule' do
    structural_arr = PC.array_rule('/samples/*/attributes')
    literal_arr    = PC.array_rule('/samples/3/attributes')
    assert_equal structural_arr.object_id, literal_arr.object_id,
                 'literal indices must map to the same cached rule object'

    structural_vol = PC.volatile?('/samples/*/provenance')
    literal_vol    = PC.volatile?('/samples/9000/provenance')
    assert_equal structural_vol, literal_vol
  end
end
