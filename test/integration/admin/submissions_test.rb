require 'test_helper'

class AdminSubmissionsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:alice).tap { it.update!(admin: true) }

    default_headers['Authorization'] = "Bearer #{@admin.api_key}"
  end

  test 'index returns submissions across all DBs by default' do
    get admin_submissions_path

    assert_conform_schema 200

    ids = response.parsed_body.pluck('id')

    assert_includes ids, submissions(:st26).id
    assert_includes ids, submissions(:bioproject).id
    assert_includes ids, submissions(:biosample).id
  end

  test 'index filters by db' do
    get admin_submissions_path, params: {db: 'st26'}

    assert_response :ok

    body = response.parsed_body
    ids  = body.pluck('id')

    assert_includes     ids, submissions(:st26).id
    assert_not_includes ids, submissions(:bioproject).id

    entry = body.find { it['id'] == submissions(:st26).id }

    assert_equal 'st26',            entry['db']
    assert_equal users(:alice).uid, entry.dig('user', 'uid')
  end

  test 'index filters by user uid' do
    bob_request = SubmissionRequest.new(user: users(:bob), db: 'st26')
    attach_ddbj_record(bob_request)
    bob_request.save!

    bob_submission = Submission.new(db: 'st26', request: bob_request)
    attach_submission_files(bob_submission)
    bob_submission.save!

    get admin_submissions_path, params: {user: 'bob'}

    assert_response :ok

    ids = response.parsed_body.pluck('id')

    assert_includes     ids, bob_submission.id
    assert_not_includes ids, submissions(:st26).id
  end

  test 'index returns 403 for non-admin users' do
    default_headers['Authorization'] = "Bearer #{users(:carol).api_key}"

    with_exceptions_app do
      get admin_submissions_path
    end

    assert_response :forbidden
  end
end
