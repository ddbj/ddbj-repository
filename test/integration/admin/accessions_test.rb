require 'test_helper'

class AdminAccessionsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)
    Sequence.ensure_records!
  end

  # --- per-submission BP ---

  test 'POST creates a BP accession, stamps Project, redirects to show' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: nil, status: 'curating')

    post admin_submission_accession_path(submission)

    assert_redirected_to admin_submission_request_path(submission.request)
    assert_match(/Issued accession PRJDB/, flash[:notice])
    assert projects(:primary).reload.accession.match?(/\APRJDB\d+\z/)
    assert_equal 'accession_issued', projects(:primary).reload.status
  end

  test 'POST refuses BP when project already has accession' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: 'PRJDB000001', status: 'curating')

    post admin_submission_accession_path(submission)

    assert_redirected_to admin_submission_request_path(submission.request)
    assert_match(/Cannot issue/, flash[:alert])
    assert_equal 'PRJDB000001', projects(:primary).reload.accession
  end

  # --- per-submission BS ---

  test 'POST creates SAMD for every eligible sample, redirects to show' do
    submission = submissions(:biosample)
    samples(:first).update!(accession: nil, status: 'curating')
    samples(:second).update!(accession: nil, status: 'curating')

    post admin_submission_accession_path(submission)

    assert_redirected_to admin_submission_request_path(submission.request)
    assert_match(/Issued accession SAMD\d+/, flash[:notice])
    assert samples(:first).reload.accession.match?(/\ASAMD/)
    assert samples(:second).reload.accession.match?(/\ASAMD/)
  end

  test 'POST refuses BS when no sample is eligible' do
    submission = submissions(:biosample)
    samples(:first).update!(accession: 'SAMD00000001', status: 'public')
    samples(:second).update!(accession: 'SAMD00000002', status: 'public')

    post admin_submission_accession_path(submission)

    assert_redirected_to admin_submission_request_path(submission.request)
    assert_match(/Cannot issue/, flash[:alert])
  end

  test 'POST requires admin auth' do
    sign_in_as users(:carol)
    post admin_submission_accession_path(submissions(:bioproject))

    assert_response :forbidden
  end

  # `/**/accession` is a volatile path, so issuance produces no patch —
  # the event is the only record that it happened, and who did it.
  test 'issuance records an event because it leaves no patch behind' do
    projects(:primary).update!(accession: nil, status: 'curating')

    assert_no_difference 'submissions(:bioproject).updates.count' do
      assert_difference 'CurationEvent.count', 1 do
        post admin_submission_accession_path(submissions(:bioproject))
      end
    end

    event = CurationEvent.last

    assert_equal 'accession_issued',          event.action
    assert_equal 'admin:bob',                 event.actor
    assert_equal 'issued 1 PRJDB accession',  event.summary
  end

  test 'a refused issuance records nothing' do
    projects(:primary).update!(accession: nil, status: 'public')

    assert_no_difference 'CurationEvent.count' do
      post admin_submission_accession_path(submissions(:bioproject))
    end
  end

  # --- the summary bar offers the action only when it would succeed ---

  test 'BP overview promotes Issue PRJDB to the summary bar when the project has no accession' do
    projects(:primary).update!(accession: nil, status: 'curating')

    get admin_submission_request_path(submissions(:bioproject).request)

    assert_response :ok
    assert_match 'Issue PRJDB for 1 project',                               response.body
    assert_match admin_submission_accession_path(submissions(:bioproject)), response.body
  end

  test 'BP overview hides the Issue button when the project already has an accession' do
    projects(:primary).update!(accession: 'PRJDB000001', status: 'curating')

    get admin_submission_request_path(submissions(:bioproject).request)

    assert_response :ok
    assert_no_match 'Issue PRJDB for', response.body
  end

  # Offering a button the service would refuse just turns into an error
  # flash — say nothing is pending instead.
  test 'BP overview offers no action in a non-issuable status' do
    projects(:primary).update!(accession: nil, status: 'public')

    get admin_submission_request_path(submissions(:bioproject).request)

    assert_response :ok
    assert_no_match 'Issue PRJDB for',                 response.body
    assert_match    'Nothing is waiting on a curator', response.body
  end

  test 'BS overview offers no action when un-accessioned samples are all in a non-issuable status' do
    samples(:first).update!(accession: nil, status: 'public')
    samples(:second).update!(accession: nil, status: 'public')

    get admin_submission_request_path(submissions(:biosample).request)

    assert_response :ok
    assert_no_match 'Issue SAMD for',                  response.body
    assert_match    'Nothing is waiting on a curator', response.body
  end

  # --- cross-submission bulk_issue_accessions ---

  test 'bulk_issue_accessions issues accessions across selected submissions' do
    projects(:primary).update!(accession: nil, status: 'curating')
    samples(:first).update!(accession: nil, status: 'curating')
    samples(:second).update!(accession: nil, status: 'curating')

    post bulk_issue_accessions_admin_submissions_path,
         params: {bulk: {submission_ids: [submissions(:bioproject).id.to_s, submissions(:biosample).id.to_s]}}

    assert_redirected_to admin_submission_requests_path
    assert_match(/Issued 3 accession\(s\)/, flash[:notice])

    assert projects(:primary).reload.accession.match?(/\APRJDB/)
    assert samples(:first).reload.accession.match?(/\ASAMD/)
    assert samples(:second).reload.accession.match?(/\ASAMD/)
  end

  test 'bulk_issue_accessions collects refused reasons without halting the rest' do
    # bioproject already issued; biosample's samples are eligible
    projects(:primary).update!(accession: 'PRJDB000001', status: 'public')
    samples(:first).update!(accession: nil, status: 'curating')
    samples(:second).update!(accession: nil, status: 'curating')

    post bulk_issue_accessions_admin_submissions_path,
         params: {bulk: {submission_ids: [submissions(:bioproject).id.to_s, submissions(:biosample).id.to_s]}}

    assert_redirected_to admin_submission_requests_path
    assert_match(/1 refused/,                  flash[:notice])
    assert_match(/already has accession/,      flash[:alert].to_s)

    # The biosample side still got stamped.
    assert samples(:first).reload.accession.match?(/\ASAMD/)
  end

  test 'bulk_issue_accessions refuses empty selection' do
    post bulk_issue_accessions_admin_submissions_path, params: {bulk: {submission_ids: []}}

    assert_redirected_to admin_submission_requests_path
    assert_match(/No submissions selected/, flash[:alert])
  end

  test 'bulk_issue_accessions preserves filter params in the redirect' do
    projects(:primary).update!(accession: nil, status: 'curating')

    post bulk_issue_accessions_admin_submissions_path,
         params: {db: 'bioproject', status: 'curating',
                  bulk: {submission_ids: [submissions(:bioproject).id.to_s]}}

    assert_redirected_to admin_submission_requests_path(db: 'bioproject', status: 'curating')
  end

  test 'bulk_issue_accessions requires admin auth' do
    sign_in_as users(:carol)
    post bulk_issue_accessions_admin_submissions_path,
         params: {bulk: {submission_ids: [submissions(:bioproject).id.to_s]}}

    assert_response :forbidden
  end
end

class AdminSubmissionAccessionDisplayTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)
  end

  test 'BP show displays project.accession in the top dl when present' do
    projects(:primary).update!(accession: 'PRJDB000999')

    get admin_submission_request_path(submissions(:bioproject).request)

    assert_response :ok
    assert_match 'PRJDB000999', response.body
  end

  test 'BP show displays "— (not issued)" when project.accession is nil' do
    projects(:primary).update!(accession: nil)

    get admin_submission_request_path(submissions(:bioproject).request)

    assert_response :ok
    assert_match '— (not issued)', response.body
  end

  test 'BS overview names the first accession and counts the rest' do
    samples(:first).update!(accession: 'SAMD00000001')
    samples(:second).update!(accession: 'SAMD00000002')

    get admin_submission_request_path(submissions(:biosample).request)

    assert_response :ok
    assert_match 'SAMD00000001', response.body
    assert_match '+1 more',      response.body
  end
end
