require 'test_helper'

class AdminSessionsTest < ActionDispatch::IntegrationTest
  # --- the sign-in page --------------------------------------------------

  test 'an unauthenticated visit is sent to the curator sign-in page' do
    get admin_root_path

    assert_redirected_to new_admin_session_path(origin: '/admin')
  end

  # "Sign in required" states the system's condition. This is a place, so
  # it says what to do — and where it leads, which is what turns logging in
  # into getting back to what you were doing.
  test 'the sign-in page names the area and where login returns to' do
    get new_admin_session_path(origin: '/admin/submission_requests/1482')

    assert_response :ok
    assert_match 'Curator area',                         response.body
    assert_match 'Log in to continue',                   response.body
    assert_match '/admin/submission_requests/1482',      response.body
    assert_match '/auth/keycloak',                       response.body
  end

  test 'the sign-in page offers the submitter view as a way out' do
    get new_admin_session_path

    assert_response :ok
    assert_match WebApp.url_for, response.body
  end

  # --- no curator access -------------------------------------------------

  test 'a signed-in non-curator gets an explanation, not a bare 403' do
    sign_in_as users(:carol)

    with_exceptions_app { get admin_root_path }

    assert_response :forbidden
    assert_equal 'text/html', response.media_type
    assert_match 'no curator access', response.body
    assert_match 'carol',             response.body
  end

  # Logging in again reaches the same result, so the primary action must
  # not be the login button.
  test 'the no-access page leads to the submitter view, not back to login' do
    sign_in_as users(:carol)

    with_exceptions_app { get admin_root_path }

    assert_match WebApp.url_for, response.body
    assert_match 'Go to my submissions', response.body
  end

  test 'a curator is not shown the no-access page' do
    sign_in_as users(:bob)

    get admin_root_path

    assert_response :ok
    assert_no_match(/no curator access/, response.body)
  end
end
