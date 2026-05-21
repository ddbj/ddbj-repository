require 'test_helper'

class AdminUsersTest < ActionDispatch::IntegrationTest
  ALICE_PROFILE = {uid: 'alice', full_name: 'Alice Liddell', email: 'alice@example.com', organization: 'Wonderland',   account_type_number: 'general'}.freeze
  BOB_PROFILE   = {uid: 'bob',   full_name: 'Bob Builder',   email: 'bob@example.com',   organization: 'Construction', account_type_number: 'general'}.freeze
  CAROL_PROFILE = {uid: 'carol', full_name: 'Carol King',    email: 'carol@example.com', organization: 'Music',        account_type_number: 'general'}.freeze

  setup do
    sign_in_as users(:bob)
  end

  test 'index lists active users with profile fetched from cloakman' do
    stub_cloakman_lookup [ALICE_PROFILE]

    get admin_users_path

    assert_response :ok
    assert_match 'alice',         response.body
    assert_match 'Alice Liddell', response.body
  end

  test 'index includes inactive users when include_inactive=1' do
    stub_cloakman_lookup [ALICE_PROFILE, BOB_PROFILE, CAROL_PROFILE]

    get admin_users_path, params: {include_inactive: '1'}

    assert_response :ok
    assert_match 'Alice Liddell', response.body
    assert_match 'Bob Builder',   response.body
    assert_match 'Carol King',    response.body
  end

  test 'index filters cloakman search results to registered active users' do
    stub_request(:get, 'http://cloakman.example.com/api/users')
      .with(query: {query: 'ali'})
      .to_return(
        status:  200,
        body:    [
          ALICE_PROFILE,
          {uid: 'alicia', full_name: 'Alicia Keys', email: 'alicia@example.com', organization: 'Music', account_type_number: 'general'}
        ].to_json,
        headers: {'Content-Type' => 'application/json'}
      )

    get admin_users_path, params: {query: 'ali'}

    assert_response :ok
    assert_match    'Alice Liddell', response.body
    assert_no_match 'Alicia Keys',   response.body
  end

  test 'show returns the user profile combined with the admin flag and counts' do
    stub_cloakman_lookup [ALICE_PROFILE]

    get admin_user_path(uid: 'alice')

    assert_response :ok
    assert_match 'Alice Liddell', response.body
    assert_match 'Wonderland',    response.body
  end

  test 'show returns 404 when the user is not registered locally' do
    with_exceptions_app do
      get admin_user_path(uid: 'never-seen')
    end

    assert_response :not_found
  end

  test 'show includes the persisted notes' do
    users(:alice).update!(notes: 'Existing note')

    stub_cloakman_lookup [ALICE_PROFILE]

    get admin_user_path(uid: 'alice')

    assert_response :ok
    assert_match 'Existing note', response.body
  end

  test 'update persists notes and redirects with a flash message' do
    stub_cloakman_lookup [ALICE_PROFILE]

    patch admin_user_path(uid: 'alice'), params: {user: {notes: 'Be careful with this account.'}}

    assert_redirected_to admin_user_path(uid: 'alice')
    assert_equal 'Notes saved.',                  flash[:notice]
    assert_equal 'Be careful with this account.', users(:alice).reload.notes
  end

  test 'update returns 403 for non-admin users' do
    sign_in_as users(:carol)

    with_exceptions_app do
      patch admin_user_path(uid: 'alice'), params: {user: {notes: 'nope'}}
    end

    assert_response :forbidden
  end

  test 'show returns 404 when cloakman has no matching profile' do
    stub_cloakman_lookup [], uids: %w[alice]

    with_exceptions_app do
      get admin_user_path(uid: 'alice')
    end

    assert_response :not_found
  end

  test 'index returns 403 for non-admin users' do
    sign_in_as users(:carol)

    with_exceptions_app do
      get admin_users_path
    end

    assert_response :forbidden
  end

  test 'show returns 403 for non-admin users' do
    sign_in_as users(:carol)

    with_exceptions_app do
      get admin_user_path(uid: 'alice')
    end

    assert_response :forbidden
  end

  test 'proxy_login redirects to web with the proxy_login query parameter' do
    post admin_user_proxy_login_path(user_uid: 'alice')

    assert_redirected_to %r{http://repository\.example\.com:4200/web/\?proxy_login=alice}
  end
end
