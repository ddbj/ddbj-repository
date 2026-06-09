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

    assert_redirected_to admin_submission_path(submission)
    assert_match(/Issued accession PRJDB/, flash[:notice])
    assert projects(:primary).reload.accession.match?(/\APRJDB\d+\z/)
    assert_equal 'accession_issued', projects(:primary).reload.status
  end

  test 'POST refuses BP when project already has accession' do
    submission = submissions(:bioproject)
    projects(:primary).update!(accession: 'PRJDB000001', status: 'curating')

    post admin_submission_accession_path(submission)

    assert_redirected_to admin_submission_path(submission)
    assert_match(/Cannot issue/, flash[:alert])
    assert_equal 'PRJDB000001', projects(:primary).reload.accession
  end

  # --- per-submission BS ---

  test 'POST creates SAMD for every eligible sample, redirects to show' do
    submission = submissions(:biosample)
    samples(:first).update!(accession: nil, status: 'curating')
    samples(:second).update!(accession: nil, status: 'curating')

    post admin_submission_accession_path(submission)

    assert_redirected_to admin_submission_path(submission)
    assert_match(/Issued accession SAMD\d+/, flash[:notice])
    assert samples(:first).reload.accession.match?(/\ASAMD/)
    assert samples(:second).reload.accession.match?(/\ASAMD/)
  end

  test 'POST refuses BS when no sample is eligible' do
    submission = submissions(:biosample)
    samples(:first).update!(accession: 'SAMD00000001', status: 'public')
    samples(:second).update!(accession: 'SAMD00000002', status: 'public')

    post admin_submission_accession_path(submission)

    assert_redirected_to admin_submission_path(submission)
    assert_match(/Cannot issue/, flash[:alert])
  end

  test 'POST requires admin auth' do
    sign_in_as users(:carol)
    post admin_submission_accession_path(submissions(:bioproject))

    assert_response :forbidden
  end

  # --- show page renders Issue button only when actionable ---

  test 'BP show renders Issue PRJDB button when project has no accession' do
    projects(:primary).update!(accession: nil, status: 'curating')

    get admin_submission_path(submissions(:bioproject))

    assert_response :ok
    assert_match 'Issue PRJDB accession',                                  response.body
    assert_match admin_submission_accession_path(submissions(:bioproject)), response.body
  end

  test 'BP show hides Issue button when project already has accession' do
    projects(:primary).update!(accession: 'PRJDB000001', status: 'curating')

    get admin_submission_path(submissions(:bioproject))

    assert_response :ok
    assert_no_match 'Issue PRJDB accession', response.body
  end

  # --- cross-submission bulk_issue_accessions ---

  test 'bulk_issue_accessions issues accessions across selected submissions' do
    projects(:primary).update!(accession: nil, status: 'curating')
    samples(:first).update!(accession: nil, status: 'curating')
    samples(:second).update!(accession: nil, status: 'curating')

    post bulk_issue_accessions_admin_submissions_path,
         params: {bulk: {submission_ids: [submissions(:bioproject).id.to_s, submissions(:biosample).id.to_s]}}

    assert_redirected_to admin_submissions_path
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

    assert_redirected_to admin_submissions_path
    assert_match(/1 refused/,                  flash[:notice])
    assert_match(/already has accession/,      flash[:alert].to_s)

    # The biosample side still got stamped.
    assert samples(:first).reload.accession.match?(/\ASAMD/)
  end

  test 'bulk_issue_accessions refuses empty selection' do
    post bulk_issue_accessions_admin_submissions_path, params: {bulk: {submission_ids: []}}

    assert_redirected_to admin_submissions_path
    assert_match(/No submissions selected/, flash[:alert])
  end

  test 'bulk_issue_accessions preserves filter params in the redirect' do
    projects(:primary).update!(accession: nil, status: 'curating')

    post bulk_issue_accessions_admin_submissions_path,
         params: {db: 'bioproject', status: 'curating',
                  bulk: {submission_ids: [submissions(:bioproject).id.to_s]}}

    assert_redirected_to admin_submissions_path(db: 'bioproject', status: 'curating')
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

    get admin_submission_path(submissions(:bioproject))

    assert_response :ok
    assert_match 'PRJDB000999', response.body
  end

  test 'BP show displays "— (not issued)" when project.accession is nil' do
    projects(:primary).update!(accession: nil)

    get admin_submission_path(submissions(:bioproject))

    assert_response :ok
    assert_match '— (not issued)', response.body
  end

  test 'BS show displays "X / Y sample(s) issued" in the top dl' do
    samples(:first).update!(accession: 'SAMD00000001')
    samples(:second).update!(accession: nil)

    get admin_submission_path(submissions(:biosample))

    assert_response :ok
    assert_match '1 / 2 sample(s) issued', response.body
  end
end
