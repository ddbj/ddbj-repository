require 'test_helper'

# The one place a run of numbers is turned into something to read. Both
# readers — the run page and the activity feed — go through here, and the
# feed's copy is written once and kept, so getting it wrong is not
# something a later fix reaches.
class AccessionRunTest < ActiveSupport::TestCase
  test 'a run of numbers is shown as a range' do
    # Trimmed to where they diverge: the run page's job is to say which
    # numbers exist, and eighteen lines of SAMD do not say it better.
    assert_equal 'SAMD00412919–936', AccessionRun.label((412_919..412_936).map { format('SAMD%08d', it) })
  end

  # "SAMD00412919–20" reads as a two-digit number rather than as the tail
  # of a twelve-digit one, so the range never trims below three digits
  # even when only the last one changes.
  test 'a short divergence still shows three digits' do
    assert_equal 'SAMD00412919–920', AccessionRun.label(%w[SAMD00412919 SAMD00412920])
  end

  test 'one accession is shown as itself' do
    assert_equal 'PRJDB42369', AccessionRun.label(%w[PRJDB42369])
  end

  test 'nothing issued has no range' do
    assert_nil AccessionRun.label([])
  end

  # The order they were allocated in is not the order they read in, and
  # the range has to name the true ends.
  test 'the range is the extremes, not the first and last written' do
    assert_equal 'SAMD00000001–100', AccessionRun.label(%w[SAMD00000050 SAMD00000100 SAMD00000001])
  end
end
