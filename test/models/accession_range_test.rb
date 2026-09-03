require 'test_helper'

class AccessionRangeTest < ActiveSupport::TestCase
  test 'reads a range written as first and last' do
    range = AccessionRange.parse('SAMD00000001-SAMD00000050')

    assert_equal 'SAMD', range.prefix
    assert_equal 1,      range.from
    assert_equal 50,     range.to
  end

  test 'covers what falls inside it and nothing else' do
    range = AccessionRange.parse('SAMD00000010-SAMD00000020')

    assert range.cover?('SAMD00000010')
    assert range.cover?('SAMD00000015')
    assert range.cover?('SAMD00000020')

    assert_not range.cover?('SAMD00000009')
    assert_not range.cover?('SAMD00000021')
  end

  # The reason the comparison is on the number rather than on the string:
  # BioProject does not pad, so lexically PRJDB1000 sorts before PRJDB999
  # and a range written across that boundary would share the wrong block —
  # silently, and only for one of the three databases.
  test 'compares numerically, not lexically' do
    range = AccessionRange.parse('PRJDB999-PRJDB1000')

    assert range.cover?('PRJDB1000')
    assert_not range.cover?('PRJDB998')
    assert_not_equal range.cover?('PRJDB1000'), 'PRJDB1000'.between?('PRJDB999', 'PRJDB1000')
  end

  test 'a prefix from a different database is not covered' do
    assert_not AccessionRange.parse('SAMD00000001-SAMD00000050').cover?('PRJDB000001')
  end

  test 'reads the two ends either way round' do
    backwards = AccessionRange.parse('PRJDB10-PRJDB1')

    assert_equal 1,  backwards.from
    assert_equal 10, backwards.to
  end

  # What a refusal quotes back has to be what the reader typed. Told that
  # nothing falls in `SAMD9000-SAMD9999` when they wrote the padded form,
  # they have to rule out the padding before they can see the real
  # mistake, which is usually the prefix.
  test 'says itself as it was written' do
    assert_equal 'SAMD00009000-SAMD00009999', AccessionRange.parse('SAMD00009000-SAMD00009999').to_s
  end

  test 'refuses what is not a range' do
    assert_nil AccessionRange.parse('PRJDB1')
    assert_nil AccessionRange.parse('PRJDB1-PRJDB2-PRJDB3')
    assert_nil AccessionRange.parse('PRJDB1-SAMD00000002'), 'the two ends have to name the same series'
    assert_nil AccessionRange.parse('PRJDB-PRJDB2')
    assert_nil AccessionRange.parse('-PRJDB2')
  end

  # A token with a hyphen was meant as a range, so an unreadable one is
  # reported as a bad range rather than looked up as an accession.
  test 'says whether a token was written as a range at all' do
    assert AccessionRange.written_as_range?('PRJDB1-PRJDB2')
    assert AccessionRange.written_as_range?('nonsense-')
    assert_not AccessionRange.written_as_range?('PRJDB1')
  end
end
