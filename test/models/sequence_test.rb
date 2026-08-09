require 'test_helper'

class SequenceTest < ActiveSupport::TestCase
  test 'allocate! generates sequential accession numbers' do
    assert_equal 'QP000001', Sequence.allocate!(:jpo_na, 1).last

    Sequence.find_by!(scope: 'jpo_na').update! next: 1000000

    assert_equal 'QQ000001', Sequence.allocate!(:jpo_na, 1).last
  end

  test 'allocate! spans prefixes within a single call' do
    Sequence.ensure_records!
    Sequence.find_by!(scope: 'jpo_na').update! prefix: 'QP', next: 999999

    assert_equal %w[QP999999 QQ000001 QQ000002], Sequence.allocate!(:jpo_na, 3)
  end

  # 最後の prefix の最終番号でぴったり終わる採番は成立している。ここで Exhausted に
  # すると、全件成功しているのにロールバックされ、その番号は永久に払い出せなくなる。
  test 'allocate! issues the last number of the last prefix' do
    Sequence.ensure_records!
    Sequence.find_by!(scope: 'jpo_na').update! prefix: 'QX', next: 999998

    assert_equal %w[QX999998 QX999999], Sequence.allocate!(:jpo_na, 2)

    assert_raises Sequence::Exhausted do
      Sequence.allocate! :jpo_na, 1
    end
  end

  # 足りないときは 1 件も払い出さない。ApplySubmissionRequestJob はこれと
  # create_submission! を同一トランザクションに置いているので、部分的な消費が
  # 起きると「番号が消費された ⟺ submission が存在する」が崩れる。
  test 'allocate! consumes nothing when the remaining capacity is short' do
    Sequence.ensure_records!
    Sequence.find_by!(scope: 'jpo_na').update! prefix: 'QX', next: 999998

    assert_raises Sequence::Exhausted do
      Sequence.allocate! :jpo_na, 3
    end

    seq = Sequence.find_by!(scope: 'jpo_na')

    assert_equal 'QX',   seq.prefix
    assert_equal 999998, seq.next
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
