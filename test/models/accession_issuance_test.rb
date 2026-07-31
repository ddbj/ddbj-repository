require 'test_helper'

# What the run page reads off a finished issuance. The issuing itself is
# test/services/accession_issue_test.rb.
class AccessionIssuanceTest < ActiveSupport::TestCase
  def build(accessions)
    AccessionIssuance.new(submission: submissions(:biosample), actor: 'admin:bob', accessions:)
  end

  test 'a run of numbers is shown as a range' do
    # Trimmed to where they diverge: the run page's job is to say which
    # numbers exist, and eighteen lines of SAMD do not say it better.
    assert_equal 'SAMD00412919–936', build((412_919..412_936).map { format('SAMD%08d', it) }).accession_range
  end

  # "SAMD00412919–20" reads as a two-digit number rather than as the tail
  # of a twelve-digit one, so the range never trims below three digits
  # even when only the last one changes.
  test 'a short divergence still shows three digits' do
    assert_equal 'SAMD00412919–920', build(%w[SAMD00412919 SAMD00412920]).accession_range
  end

  test 'one accession is shown as itself' do
    assert_equal 'PRJDB42369', build(%w[PRJDB42369]).accession_range
  end

  test 'nothing issued has no range' do
    assert_nil build([]).accession_range
  end

  # The order they were allocated in is not the order they read in, and
  # the range has to name the true ends.
  test 'the range is the extremes, not the first and last written' do
    assert_equal 'SAMD00000001–100', build(%w[SAMD00000050 SAMD00000100 SAMD00000001]).accession_range
  end
end
