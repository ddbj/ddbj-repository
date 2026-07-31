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

    assert_redirected_to admin_submission_accession_path(submission, issuance)
    assert_equal 'admin:bob', issuance.actor
    assert issuance.queued_status?, 'running is what the job claims, not what the controller assumes'
  end

  # Which samples were asked for is stored as the curator expressed it —
  # a filter stays a filter, so the job re-derives it rather than acting
  # on a snapshot of ids taken when the page was rendered.
  test 'a filtered selection is stored as its filter, not as resolved ids' do
    submission = submissions(:biosample)

    post admin_submission_accessions_path(submission),
         params: {status: 'private', bulk_sample: {scope: 'filtered'}}

    targeting = submission.accession_issuances.sole.targeting

    assert_equal 'filtered',                targeting['scope']
    assert_equal({'status' => %w[private]}, targeting['filter'])
  end

  test 'a checkbox selection is stored as the ids that were ticked' do
    submission = submissions(:biosample)

    post admin_submission_accessions_path(submission),
         params: {bulk_sample: {scope: 'selected', sample_ids: [samples(:first).id]}}

    targeting = submission.accession_issuances.sole.targeting

    assert_equal 'selected',           targeting['scope']
    assert_equal [samples(:first).id], targeting['sample_ids']
  end

  # A garbled scope would otherwise widen a handful of checked rows into
  # all 100K, and an issuance cannot be taken back once the Sequence has
  # moved.
  test 'POST refuses an unrecognised target rather than widening it' do
    submission = submissions(:biosample)

    assert_no_enqueued_jobs only: IssueAccessionsJob do
      post admin_submission_accessions_path(submission), params: {bulk_sample: {scope: 'everything'}}
    end

    assert_match(/Cannot issue accession/, flash[:alert])
  end

  test 'POST refuses an empty checkbox selection' do
    submission = submissions(:biosample)

    assert_no_enqueued_jobs only: IssueAccessionsJob do
      post admin_submission_accessions_path(submission), params: {bulk_sample: {scope: 'selected', sample_ids: []}}
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

    assert_redirected_to admin_submission_requests_path
    assert_match(/Issuing accessions for 2 submission/, flash[:notice])

    assert_equal 1, submissions(:bioproject).accession_issuances.count
    assert_equal 1, submissions(:biosample).accession_issuances.count
  end

  test 'bulk_issue_accessions refuses empty selection' do
    assert_no_enqueued_jobs only: IssueAccessionsJob do
      post bulk_issue_accessions_admin_submissions_path, params: {bulk: {submission_ids: []}}
    end

    assert_redirected_to admin_submission_requests_path
    assert_match(/No submissions selected/, flash[:alert])
  end

  test 'bulk_issue_accessions preserves filter params in the redirect' do
    post bulk_issue_accessions_admin_submissions_path,
         params: {q: 'PRJDB', db: %w[bioproject], status: %w[curating],
                  bulk: {submission_ids: [submissions(:bioproject).id.to_s]}}

    assert_redirected_to admin_submission_requests_path(q: 'PRJDB', db: %w[bioproject], status: %w[curating])
  end

  test 'bulk_issue_accessions requires admin auth' do
    sign_in_as users(:carol)
    post bulk_issue_accessions_admin_submissions_path,
         params: {bulk: {submission_ids: [submissions(:bioproject).id.to_s]}}

    assert_response :forbidden
  end
end
