require 'test_helper'

class AdminSubmissionsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:alice).tap { it.update!(admin: true) }

    default_headers['Authorization'] = "Bearer #{@admin.api_key}"
  end

  test 'index returns submissions for the requested db with the owning user' do
    get admin_submissions_path(db: 'st26')

    assert_conform_schema 200

    body = response.parsed_body
    ids  = body.pluck('id')

    assert_includes     ids, submissions(:st26).id
    assert_not_includes ids, submissions(:bioproject).id

    entry = body.find { it['id'] == submissions(:st26).id }

    assert_equal users(:alice).uid, entry.dig('user', 'uid')
  end

  test 'index returns 403 for non-admin users' do
    default_headers['Authorization'] = "Bearer #{users(:carol).api_key}"

    with_exceptions_app do
      get admin_submissions_path(db: 'st26')
    end

    assert_response :forbidden
  end
end
