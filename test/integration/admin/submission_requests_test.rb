require 'test_helper'

class AdminSubmissionRequestsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)
  end

  test 'index returns requests across all DBs by default' do
    get admin_submission_requests_path

    assert_response :ok
    assert_match "Request-#{submission_requests(:st26).id}",       response.body
    assert_match "Request-#{submission_requests(:bioproject).id}", response.body
    assert_match "Request-#{submission_requests(:biosample).id}",  response.body
  end

  test 'index filters by db' do
    get admin_submission_requests_path, params: {db: 'st26'}

    assert_response :ok
    assert_match    "Request-#{submission_requests(:st26).id}",       response.body
    assert_no_match "Request-#{submission_requests(:bioproject).id}", response.body
  end

  test 'index filters by user uid' do
    carol_request = SubmissionRequest.new(user: users(:carol), db: 'st26')
    attach_ddbj_record(carol_request)
    carol_request.save!

    get admin_submission_requests_path, params: {user: 'carol'}

    assert_response :ok
    assert_match    "Request-#{carol_request.id}",                response.body
    assert_no_match "Request-#{submission_requests(:st26).id}",   response.body
  end

  test 'index returns 403 for non-admin users' do
    sign_in_as users(:carol)

    with_exceptions_app do
      get admin_submission_requests_path
    end

    assert_response :forbidden
  end
end
