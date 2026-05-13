require 'test_helper'

class AdminUsersTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:alice).tap { it.update!(admin: true) }

    default_headers['Authorization'] = "Bearer #{@admin.api_key}"
  end

  test 'index proxies to cloakman and returns user list' do
    body = [
      {
        uid:                 'alice',
        full_name:           'Alice Liddell',
        email:               'alice@example.com',
        organization:        'Wonderland',
        account_type_number: 'general'
      }
    ]

    stub_request(:get, 'http://cloakman.example.com/api/users')
      .with(headers: {Authorization: 'Bearer notasecret'})
      .to_return(status: 200, body: body.to_json, headers: {'Content-Type' => 'application/json'})

    get admin_users_path

    assert_conform_schema 200

    assert_equal body.map(&:stringify_keys), response.parsed_body
  end

  test 'index forwards query param to cloakman' do
    stub = stub_request(:get, 'http://cloakman.example.com/api/users')
      .with(query: {query: 'ali'})
      .to_return(status: 200, body: '[]', headers: {'Content-Type' => 'application/json'})

    get admin_users_path, params: {query: 'ali'}

    assert_response :ok
    assert_requested stub
  end

  test 'index returns 403 for non-admin users' do
    default_headers['Authorization'] = "Bearer #{users(:carol).api_key}"

    with_exceptions_app do
      get admin_users_path
    end

    assert_response :forbidden
  end
end
