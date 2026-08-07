require 'test_helper'

# Starting an issuance: what the button enqueues, and what it refuses to
# enqueue. What the job then does is test/jobs/issue_accessions_job_test.rb;
# whether the button is offered at all is test/system/overview_test.rb.
class AdminAccessionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:bob)
    Sequence.ensure_records!
  end

  test 'POST starts an issuance and sends the curator to watch it' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    assert_enqueued_with job: IssueAccessionsJob do
      post admin_submission_accessions_path(submission)
    end

    issuance = submission.accession_issuances.sole

    # To the run, not to the issuance: one press is one run, whether it
    # covered one submission or ten, and that is the page the outcome
    # stays on.
    assert_redirected_to admin_accession_issuance_run_path(issuance.run)
    assert_equal 'admin:bob', issuance.actor
    assert issuance.queued_status?, 'running is what the job claims, not what the controller assumes'
  end

  # Which samples were asked for is stored as the curator expressed it —
  # a filter stays a filter, so the job re-derives it rather than acting
  # on a snapshot of ids taken when the page was rendered.
  test 'a filtered selection is stored as its filter, not as resolved ids' do
    submission = submissions(:biosample)

    post admin_submission_accessions_path(submission),
         params: {status: 'private', bulk_row: {scope: 'filtered'}}

    targeting = submission.accession_issuances.sole.targeting

    assert_equal 'filtered',                targeting['scope']
    assert_equal({'status' => %w[private]}, targeting['filter'])
  end

  test 'a checkbox selection is stored as the ids that were ticked' do
    submission = submissions(:biosample)

    post admin_submission_accessions_path(submission),
         params: {bulk_row: {scope: 'selected', ids: [samples(:first).id]}}

    targeting = submission.accession_issuances.sole.targeting

    assert_equal 'selected',           targeting['scope']
    assert_equal [samples(:first).id], targeting['ids']
    assert_equal [samples(:first).id],
                 AccessionIssuance.new(submission:, targeting:).send(:target_rows).ids
  end

  # A garbled scope would otherwise widen a handful of checked rows into
  # all 100K, and an issuance cannot be taken back once the Sequence has
  # moved.
  test 'POST refuses an unrecognised target rather than widening it' do
    submission = submissions(:biosample)

    assert_no_enqueued_jobs only: IssueAccessionsJob do
      post admin_submission_accessions_path(submission), params: {bulk_row: {scope: 'everything'}}
    end

    assert_match(/Cannot issue accession/, flash[:alert])
  end

  test 'POST refuses an empty checkbox selection' do
    submission = submissions(:biosample)

    assert_no_enqueued_jobs only: IssueAccessionsJob do
      post admin_submission_accessions_path(submission), params: {bulk_row: {scope: 'selected', ids: []}}
    end

    assert_match(/No samples selected/, flash[:alert])
  end

  test 'POST requires admin auth' do
    sign_in_as users(:carol)
    post admin_submission_accessions_path(submissions(:bioproject))

    assert_response :forbidden
  end

  # --- cross-submission bulk_issue_accessions ---

  # One job each, so a refusal on one cannot stall the rest — they no
  # longer share a request, a transaction, or the Sequence lock.
  test 'bulk_issue_accessions starts one issuance per selected submission' do
    assert_enqueued_jobs 2, only: IssueAccessionsJob do
      post bulk_issue_accessions_admin_submissions_path,
           params: {bulk: {submission_ids: [submissions(:bioproject).id.to_s, submissions(:biosample).id.to_s]}}
    end

    run = AccessionIssuanceRun.last

    assert_redirected_to admin_accession_issuance_run_path(run)
    assert_equal 2, run.issuances.count
    assert_equal 'All requests (2 submissions)', run.origin
  end

  test 'bulk_issue_accessions refuses empty selection' do
    assert_no_enqueued_jobs only: IssueAccessionsJob do
      post bulk_issue_accessions_admin_submissions_path, params: {bulk: {submission_ids: []}}
    end

    assert_redirected_to admin_submission_requests_path
    assert_match(/No submissions selected/, flash[:alert])
  end

  # The confirmation is what carries the filter now; the run page is
  # where the press lands, and it is not filtered by anything.
  test 'the confirmation keeps the ledger filter on its own form' do
    projects(:primary).update!(accession: nil, status: 'curating')

    post confirm_issue_accessions_admin_submissions_path,
         params: {q: 'PRJDB', db: %w[bioproject], status: %w[curating],
                  bulk: {submission_ids: [submissions(:bioproject).id.to_s]}}

    assert_response :ok
    assert_match 'Accession numbers are permanent', response.body
    assert_match CGI.escapeHTML(bulk_issue_accessions_admin_submissions_path(q: 'PRJDB', db: %w[bioproject], status: %w[curating])),
                 response.body
  end

  # The counts are the promise the dialog makes, so a submission an
  # earlier press is still working on has to be named as skipped rather
  # than counted — the job would refuse it, and the curator would have
  # confirmed a number that never got allocated.
  test 'the confirmation skips a submission that is already issuing' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    submission.accession_issuances.create!(actor: 'admin:alice', started_at: Time.current)

    post confirm_issue_accessions_admin_submissions_path,
         params: {bulk: {submission_ids: [submission.id.to_s]}}

    assert_response :ok
    assert_match 'already issuing', response.body
    assert_match 'Nothing to issue', response.body
  end

  test 'bulk_issue_accessions requires admin auth' do
    sign_in_as users(:carol)
    post bulk_issue_accessions_admin_submissions_path,
         params: {bulk: {submission_ids: [submissions(:bioproject).id.to_s]}}

    assert_response :forbidden
  end
end
