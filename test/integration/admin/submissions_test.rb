require 'test_helper'

class AdminSubmissionsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)
  end

  test 'index returns submissions across all DBs by default' do
    get admin_submissions_path

    assert_response :ok
    assert_match "Submission-#{submissions(:st26).id}",       response.body
    assert_match "Submission-#{submissions(:bioproject).id}", response.body
    assert_match "Submission-#{submissions(:biosample).id}",  response.body
  end

  test 'index filters by db' do
    get admin_submissions_path, params: {db: 'st26'}

    assert_response :ok
    assert_match    "Submission-#{submissions(:st26).id}",       response.body
    assert_no_match "Submission-#{submissions(:bioproject).id}", response.body
  end

  test 'index filters by user uid' do
    carol_request = SubmissionRequest.new(user: users(:carol), db: 'st26')
    attach_ddbj_record(carol_request)
    carol_request.save!

    carol_submission = Submission.new(db: 'st26', user: users(:carol), request: carol_request)
    attach_submission_files(carol_submission)
    carol_submission.save!

    get admin_submissions_path, params: {user: 'carol'}

    assert_response :ok
    assert_match    "Submission-#{carol_submission.id}",     response.body
    assert_no_match "Submission-#{submissions(:st26).id}",   response.body
  end

  test 'index returns 403 for non-admin users' do
    sign_in_as users(:carol)

    with_exceptions_app do
      get admin_submissions_path
    end

    assert_response :forbidden
  end
end
