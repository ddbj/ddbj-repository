require 'test_helper'

class SequenceTest < ActiveSupport::TestCase
  test 'allocate! generates sequential accession numbers' do
    assert_equal 'QP000001', Sequence.allocate!(:jpo_na, 1).last

    Sequence.find_by!(scope: 'jpo_na').update! next: 1000000

    assert_equal 'QQ000001', Sequence.allocate!(:jpo_na, 1).last
  end

  test 'bp scope emits PRJDB-prefixed numbers without zero padding' do
    Sequence.ensure_records!
    Sequence.find_by!(scope: 'bp').update! next: 42366

    assert_equal %w[PRJDB42366 PRJDB42367], Sequence.allocate!(:bp, 2)
  end

  test 'bs scope emits SAMD-prefixed numbers with 8-digit zero padding' do
    Sequence.ensure_records!
    Sequence.find_by!(scope: 'bs').update! next: 1921307

    assert_equal %w[SAMD01921307 SAMD01921308], Sequence.allocate!(:bs, 2)
  end
end
