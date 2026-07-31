require 'test_helper'

# The run record and its dismissal. What the summary says is
# test/system/accession_summary_test.rb.
class AdminAccessionIssuanceRunsTest < ActionDispatch::IntegrationTest
  setup do
    @run = AccessionIssuanceRun.create!(actor: 'admin:bob', started_at: Time.current,
                                        origin: 'All requests (1 submission)')

    @run.issuances.create!(submission: submissions(:bioproject), actor: @run.actor,
                           started_at: Time.current, finished_at: Time.current,
                           status: 'completed', accessions: %w[PRJDB19940])
  end

  test 'dismissing puts the summary away' do
    sign_in_as users(:bob)

    patch dismiss_admin_accession_issuance_run_path(@run)

    assert_redirected_to admin_submission_requests_path
    assert_predicate @run.reload, :dismissed?
  end

  # Not an ownership rule for its own sake: the summary answers "what did
  # the thing I just did do", so it is not someone else's to put away —
  # and a curator returning to a dismissed ledger would have no way to
  # tell it had been.
  # The ledger has one slot. Dismissing the press you are looking at and
  # leaving the one before it undismissed would put the older result back
  # on screen, which reads as the dismissal having failed.
  test 'dismissing clears the runs behind it too' do
    sign_in_as users(:bob)

    older = AccessionIssuanceRun.create!(actor: 'admin:bob', started_at: 1.hour.ago,
                                         origin: 'All requests (1 submission)')

    newer = AccessionIssuanceRun.create!(actor: 'admin:bob', started_at: 1.minute.from_now,
                                         origin: 'All requests (1 submission)')

    patch dismiss_admin_accession_issuance_run_path(@run)

    assert_predicate     older.reload, :dismissed?
    assert_predicate     @run.reload,  :dismissed?
    assert_not_predicate newer.reload, :dismissed?
  end

  test 'another curator cannot dismiss my summary' do
    sign_in_as users(:dave)

    patch dismiss_admin_accession_issuance_run_path(@run)

    assert_response :not_found
    assert_not_predicate @run.reload, :dismissed?
  end

  test 'the run page is readable by any curator' do
    sign_in_as users(:dave)

    get admin_accession_issuance_run_path(@run)

    assert_response :success
    assert_match 'PRJDB19940', response.body
  end

  test 'a non-admin gets nothing' do
    sign_in_as users(:carol)

    get admin_accession_issuance_run_path(@run)

    assert_response :forbidden
  end
end
