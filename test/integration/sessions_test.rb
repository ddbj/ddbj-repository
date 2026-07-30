require 'test_helper'

class SessionsTest < ActionDispatch::IntegrationTest
  def mock_keycloak(user, email: nil)
    OmniAuth.config.mock_auth[:keycloak] = OmniAuth::AuthHash.new(
      'provider' => 'keycloak',
      'uid'      => user.uid,

      'info' => {
        'email' => email
      },

      'extra' => {
        'raw_info' => {
          'preferred_username'  => user.uid,
          'account_type_number' => user.admin? ? SessionsController::ADMIN_ACCOUNT_TYPE : 1
        }
      }
    )
  end

  test 'admin-origin login mints the session cookie and returns to admin' do
    mock_keycloak(users(:bob))

    get '/auth/keycloak/callback', env: {'omniauth.origin' => '/admin/users'}

    assert_redirected_to '/admin/users'
    assert_equal users(:bob).id, session[:user_id]
  end

  test 'web-origin login issues a JWT to the web client without an admin session' do
    mock_keycloak(users(:alice))

    get '/auth/keycloak/callback' # no admin origin → web branch

    assert_match %r{/web/login\?token=}, response.location
    assert_nil session[:user_id] # a web login must not leak an admin session
  end

  # Mail delivery reads users.email, so login is the primary way it stays
  # current (SyncUserEmailsJob covers accounts that never log in).
  test 'login refreshes the stored email from the token' do
    mock_keycloak(users(:alice), email: 'alice.new@example.com')

    get '/auth/keycloak/callback'

    assert_equal 'alice.new@example.com', users(:alice).reload.email
  end

  test 'a token without an email keeps the address we already know' do
    mock_keycloak(users(:alice)) # no email claim

    get '/auth/keycloak/callback'

    assert_equal 'alice@example.com', users(:alice).reload.email
  end

  test 'admin logout clears the session and returns to the admin login' do
    sign_in_as users(:bob)
    assert session[:user_id]

    delete admin_session_path

    assert_redirected_to new_admin_session_path
    assert_nil session[:user_id]
  end
end
