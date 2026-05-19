require 'test_helper'

class AdminSubmissionRequestsTest < ActionDispatch::IntegrationTest
  setup do
    default_headers['Authorization'] = "Bearer #{users(:bob).api_key}"
  end

  test 'index returns requests across all DBs by default' do
    get admin_submission_requests_path

    assert_conform_schema 200

    ids = response.parsed_body.pluck('id')

    assert_includes ids, submission_requests(:st26).id
    assert_includes ids, submission_requests(:bioproject).id
    assert_includes ids, submission_requests(:biosample).id
  end

  test 'index filters by db' do
    get admin_submission_requests_path, params: {db: 'st26'}

    assert_response :ok

    body = response.parsed_body
    ids  = body.pluck('id')

    assert_includes     ids, submission_requests(:st26).id
    assert_not_includes ids, submission_requests(:bioproject).id

    entry = body.find { it['id'] == submission_requests(:st26).id }

    assert_equal 'st26',            entry['db']
    assert_equal users(:alice).uid, entry.dig('user', 'uid')
  end

  test 'index filters by user uid' do
    carol_request = SubmissionRequest.new(user: users(:carol), db: 'st26')
    attach_ddbj_record(carol_request)
    carol_request.save!

    get admin_submission_requests_path, params: {user: 'carol'}

    assert_response :ok

    ids = response.parsed_body.pluck('id')

    assert_includes     ids, carol_request.id
    assert_not_includes ids, submission_requests(:st26).id
  end

  test 'index returns 403 for non-admin users' do
    default_headers['Authorization'] = "Bearer #{users(:carol).api_key}"

    with_exceptions_app do
      get admin_submission_requests_path
    end

    assert_response :forbidden
  end
end
