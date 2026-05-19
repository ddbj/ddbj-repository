require 'test_helper'

class AdminUsersTest < ActionDispatch::IntegrationTest
  setup do
    default_headers['Authorization'] = "Bearer #{users(:bob).api_key}"
  end

  test 'index lists active users with profile fetched from cloakman' do
    stub_request(:get, 'http://cloakman.example.com/api/users/lookup')
      .with(query: {uids: %w[alice]})
      .to_return(
        status:  200,
        body:    [{uid: 'alice', full_name: 'Alice Liddell', email: 'alice@example.com', organization: 'Wonderland', account_type_number: 'general'}].to_json,
        headers: {'Content-Type' => 'application/json'}
      )

    get admin_users_path

    assert_conform_schema 200

    body = response.parsed_body

    assert_equal %w[alice],         body.map { it['uid'] }
    assert_equal 'Alice Liddell',   body.first['full_name']
    assert_equal 3,                 body.first['submission_requests_count']
    assert_equal 3,                 body.first['submissions_count']
  end

  test 'index includes inactive users when include_inactive=1' do
    stub_request(:get, 'http://cloakman.example.com/api/users/lookup')
      .with(query: {uids: %w[alice bob carol]})
      .to_return(
        status:  200,
        body:    [
          {uid: 'alice', full_name: 'Alice Liddell', email: 'alice@example.com', organization: 'Wonderland',   account_type_number: 'general'},
          {uid: 'bob',   full_name: 'Bob Builder',   email: 'bob@example.com',   organization: 'Construction', account_type_number: 'general'},
          {uid: 'carol', full_name: 'Carol King',    email: 'carol@example.com', organization: 'Music',        account_type_number: 'general'}
        ].to_json,
        headers: {'Content-Type' => 'application/json'}
      )

    get admin_users_path, params: {include_inactive: '1'}

    assert_response :ok

    body = response.parsed_body

    assert_equal %w[alice bob carol], body.map { it['uid'] }
    assert_equal 0,                   body.find { it['uid'] == 'bob' }['submission_requests_count']
    assert_equal 0,                   body.find { it['uid'] == 'carol' }['submissions_count']
  end

  test 'index filters cloakman search results to registered active users' do
    stub_request(:get, 'http://cloakman.example.com/api/users')
      .with(query: {query: 'ali'})
      .to_return(
        status:  200,
        body:    [
          {uid: 'alice',  full_name: 'Alice Liddell', email: 'alice@example.com',  organization: 'Wonderland', account_type_number: 'general'},
          {uid: 'alicia', full_name: 'Alicia Keys',   email: 'alicia@example.com', organization: 'Music',      account_type_number: 'general'}
        ].to_json,
        headers: {'Content-Type' => 'application/json'}
      )

    get admin_users_path, params: {query: 'ali'}

    assert_response :ok
    assert_equal %w[alice], response.parsed_body.map { it['uid'] }
  end

  test 'show returns the user profile combined with the admin flag and counts' do
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
    assert_equal 3,               response.parsed_body['submission_requests_count']
    assert_equal 3,               response.parsed_body['submissions_count']
  end

  test 'show returns 404 when the user is not registered locally' do
    with_exceptions_app do
      get admin_user_path(uid: 'never-seen')
    end

    assert_response :not_found
  end

  test 'show includes the persisted notes' do
    users(:alice).update!(notes: 'Existing note')

    stub_request(:get, 'http://cloakman.example.com/api/users/lookup')
      .with(query: {uids: %w[alice]})
      .to_return(
        status:  200,
        body:    [{uid: 'alice', full_name: 'Alice Liddell', email: 'alice@example.com', organization: 'Wonderland', account_type_number: 'general'}].to_json,
        headers: {'Content-Type' => 'application/json'}
      )

    get admin_user_path(uid: 'alice')

    assert_response :ok
    assert_equal 'Existing note', response.parsed_body['notes']
  end

  test 'update persists notes and returns the refreshed detail' do
    stub_request(:get, 'http://cloakman.example.com/api/users/lookup')
      .with(query: {uids: %w[alice]})
      .to_return(
        status:  200,
        body:    [{uid: 'alice', full_name: 'Alice Liddell', email: 'alice@example.com', organization: 'Wonderland', account_type_number: 'general'}].to_json,
        headers: {'Content-Type' => 'application/json'}
      )

    patch admin_user_path(uid: 'alice'), params: {user: {notes: 'Be careful with this account.'}}, as: :json

    assert_conform_schema 200

    assert_equal 'alice',                          response.parsed_body['uid']
    assert_equal 'Be careful with this account.',  response.parsed_body['notes']
    assert_equal 'Be careful with this account.',  users(:alice).reload.notes
  end

  test 'update returns 403 for non-admin users' do
    default_headers['Authorization'] = "Bearer #{users(:carol).api_key}"

    with_exceptions_app do
      patch admin_user_path(uid: 'alice'), params: {user: {notes: 'nope'}}, as: :json
    end

    assert_response :forbidden
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
