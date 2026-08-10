require 'test_helper'

class SequenceTest < ActiveSupport::TestCase
  # 使い切りの試験は「最後の prefix」の性質を見るもので、それが QX であることは
  # 見ていない。空きが尽きたときの手当ては config に prefix を足すことなので、
  # 直書きすると障害対応の真っ最中に無関係な赤が出る。
  LAST_JPO_NA = Sequence.config.fetch(:jpo_na).last[:prefix]

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
    Sequence.find_by!(scope: 'jpo_na').update! prefix: LAST_JPO_NA, next: 999998

    assert_equal ["#{LAST_JPO_NA}999998", "#{LAST_JPO_NA}999999"], Sequence.allocate!(:jpo_na, 2)

    assert_raises Sequence::Exhausted do
      Sequence.allocate! :jpo_na, 1
    end
  end

  # 足りないときは 1 件も払い出さない。ApplySubmissionRequestJob は allocate! と
  # create_submission! を同一トランザクションに置いているので、部分的な消費が
  # 起きると「番号が消費された ⟺ submission が存在する」が崩れる。
  # （entries の COPY はそのトランザクションの外なので、そこから先は別の話）
  test 'allocate! consumes nothing when the remaining capacity is short' do
    Sequence.ensure_records!
    Sequence.find_by!(scope: 'jpo_na').update! prefix: LAST_JPO_NA, next: 999998

    assert_raises Sequence::Exhausted do
      Sequence.allocate! :jpo_na, 3
    end

    seq = Sequence.find_by!(scope: 'jpo_na')

    assert_equal LAST_JPO_NA, seq.prefix
    assert_equal 999998,      seq.next
  end

  # 使い切ったことは、どの scope でも「番号が尽きた」としか読めないメッセージで
  # 落ちてはいけない。ApplySubmissionRequestJob がこれをそのまま
  # request.error_message に書くので、登録者の画面に出る文言そのもの。
  test 'Exhausted names the scope and the prefix it ran out on' do
    Sequence.ensure_records!
    Sequence.find_by!(scope: 'jpo_na').update! prefix: LAST_JPO_NA, next: 1000000

    error = assert_raises Sequence::Exhausted do
      Sequence.allocate! :jpo_na, 2
    end

    assert_match(/jpo_na/,       error.message)
    assert_match(/#{LAST_JPO_NA}/, error.message)
    assert_match(/2/,            error.message)
  end

  # peek は allocate! が実際に出す番号でなければならない。使い切った prefix の
  # 送りは次の呼び出しに残るので、その状態を解決せずに組み立てると桁が溢れる。
  test 'peek resolves a prefix that has been used up' do
    Sequence.ensure_records!
    seq = Sequence.find_by!(scope: 'jpo_na')
    seq.update! prefix: 'QP', next: 1000000

    assert_equal 'QQ000001', seq.peek
    assert_equal seq.peek,   Sequence.allocate!(:jpo_na, 1).sole
  end

  test 'peek is nil once every prefix is used up' do
    Sequence.ensure_records!
    seq = Sequence.find_by!(scope: 'jpo_na')
    seq.update! prefix: LAST_JPO_NA, next: 1000000

    assert_nil seq.peek
    assert_equal 0, seq.remaining
  end

  # pad を無視して組み立てると PRJDB000042366 になる。allocate! が出すのは
  # PRJDB42366 で、そちらが本物。
  test 'peek honours the pad flag' do
    Sequence.ensure_records!
    seq = Sequence.find_by!(scope: 'bp')
    seq.update! next: 42366

    assert_equal 'PRJDB42366', seq.peek
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
