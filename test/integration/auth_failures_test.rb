require 'test_helper'

# `/auth/failure` was routed to an action that was never written, on an API
# controller behind `authenticate!` — so a failed login answered with a
# bare `{"error":"Unauthorized"}`. A failed login is the one moment a
# person is least equipped to interpret that.
class AuthFailuresTest < ActionDispatch::IntegrationTest
  test 'renders HTML to somebody who is not signed in' do
    get auth_failure_path

    assert_response :ok
    assert_equal 'text/html', response.media_type
    assert_match 'Login did not complete', response.body
  end

  # Cause, consequence, next step — the consequence being the part people
  # actually want: did my submission go through?
  test 'says nothing was changed and offers a way forward' do
    get auth_failure_path

    assert_match 'Nothing was submitted or changed', response.body
    assert_match 'Try again',                        response.body
    assert_match WebApp.url_for,                     response.body
  end

  # The provider's own symbol is what the help desk will ask for, so it is
  # kept — as a code, escaped, and not as the headline.
  test 'shows the provider error code without interpreting it' do
    get auth_failure_path(message: 'invalid_credentials')

    assert_response :ok
    assert_match 'invalid_credentials', response.body
  end

  test 'a crafted message cannot inject markup' do
    get auth_failure_path(message: '<script>alert(1)</script>')

    assert_response :ok
    assert_no_match(/<script>alert/, response.body)
  end

  test 'renders without a message param' do
    get auth_failure_path

    assert_response :ok
  end
end
