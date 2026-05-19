require 'test_helper'

class AdminUsersTest < ActionDispatch::IntegrationTest
  setup do
    default_headers['Authorization'] = "Bearer #{users(:bob).api_key}"
  end

  test 'index lists registered users with profile fetched from cloakman' do
    body = [
      {
        uid:                 'alice',
        full_name:           'Alice Liddell',
        email:               'alice@example.com',
        organization:        'Wonderland',
        account_type_number: 'general'
      },
      {
        uid:                 'bob',
        full_name:           'Bob Builder',
        email:               'bob@example.com',
        organization:        'Construction',
        account_type_number: 'general'
      },
      {
        uid:                 'carol',
        full_name:           'Carol King',
        email:               'carol@example.com',
        organization:        'Music',
        account_type_number: 'general'
      }
    ]

    stub = stub_request(:get, 'http://cloakman.example.com/api/users/lookup')
      .with(query: {uids: %w[alice bob carol]}, headers: {Authorization: 'Bearer notasecret'})
      .to_return(status: 200, body: body.to_json, headers: {'Content-Type' => 'application/json'})

    get admin_users_path

    assert_conform_schema 200

    assert_equal body.map(&:stringify_keys), response.parsed_body
    assert_requested stub
  end

  test 'index filters cloakman search results to registered users only' do
    body = [
      {
        uid:                 'alice',
        full_name:           'Alice Liddell',
        email:               'alice@example.com',
        organization:        'Wonderland',
        account_type_number: 'general'
      },
      {
        uid:                 'alicia',
        full_name:           'Alicia Keys',
        email:               'alicia@example.com',
        organization:        'Music',
        account_type_number: 'general'
      }
    ]

    stub_request(:get, 'http://cloakman.example.com/api/users')
      .with(query: {query: 'ali'})
      .to_return(status: 200, body: body.to_json, headers: {'Content-Type' => 'application/json'})

    get admin_users_path, params: {query: 'ali'}

    assert_response :ok
    assert_equal %w[alice], response.parsed_body.map { it['uid'] }
  end

  test 'show returns the user profile combined with the admin flag' do
    stub_request(:get, 'http://cloakman.example.com/api/users/lookup')
      .with(query: {uids: %w[alice]})
      .to_return(
        status:  200,
        body:    [{uid: 'alice', full_name: 'Alice Liddell', email: 'alice@example.com', organization: 'Wonderland', account_type_number: 'general'}].to_json,
        headers: {'Content-Type' => 'application/json'}
      )

    get admin_user_path(uid: 'alice')

    assert_conform_schema 200

    assert_equal 'alice',         response.parsed_body['uid']
    assert_equal 'Alice Liddell', response.parsed_body['full_name']
    assert_equal false,           response.parsed_body['admin']
  end

  test 'show returns 404 when the user is not registered locally' do
    with_exceptions_app do
      get admin_user_path(uid: 'never-seen')
    end

    assert_response :not_found
  end

  test 'show returns 404 when cloakman has no matching profile' do
    stub_request(:get, 'http://cloakman.example.com/api/users/lookup')
      .with(query: {uids: %w[alice]})
      .to_return(status: 200, body: '[]', headers: {'Content-Type' => 'application/json'})

    with_exceptions_app do
      get admin_user_path(uid: 'alice')
    end

    assert_response :not_found
  end

  test 'index returns 403 for non-admin users' do
    default_headers['Authorization'] = "Bearer #{users(:carol).api_key}"

    with_exceptions_app do
      get admin_users_path
    end

    assert_response :forbidden
  end

  test 'show returns 403 for non-admin users' do
    default_headers['Authorization'] = "Bearer #{users(:carol).api_key}"

    with_exceptions_app do
      get admin_user_path(uid: 'alice')
    end

    assert_response :forbidden
  end
end
