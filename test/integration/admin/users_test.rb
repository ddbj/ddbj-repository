require 'test_helper'

# What the Users endpoints do irrespective of any screen: who may reach
# them, what they do when the account is not ours, and where proxy login
# hands off to. Everything a curator reads or presses lives in
# test/system/users_test.rb.
class AdminUsersTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob) # admin
  end

  test 'show returns 404 when the user is not registered locally' do
    with_exceptions_app do
      get admin_user_path(uid: 'never-seen')
    end

    assert_response :not_found
  end

  # DDBJ Account being unreachable is a fact about the fetch, not about
  # the user — it must not turn an account that exists into one that
  # does not.
  test 'show renders without a profile rather than 404-ing' do
    stub_cloakman_lookup [], uids: %w[alice]

    get admin_user_path(uid: 'alice')

    assert_response :ok
  end

  # --- authorisation -------------------------------------------------------

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

  test 'update returns 403 for non-admin users' do
    sign_in_as users(:carol)

    with_exceptions_app do
      patch admin_user_path(uid: 'alice'), params: {user: {notes: 'nope'}}
    end

    assert_response :forbidden
  end

  # --- proxy login ---------------------------------------------------------

  # A handoff to another application rather than a screen of our own: the
  # web client is JWT-only, so proxy login hands it the admin's own token
  # plus the target, and the web login route acts as that user.
  test 'proxy_login redirects to the web login with the admin token and proxy target' do
    post admin_user_proxy_login_path(user_uid: 'alice')

    assert_redirected_to %r{http://repository\.example\.com:4200/web/auth/callback\?token=.+&proxy_login=alice}
  end
end
