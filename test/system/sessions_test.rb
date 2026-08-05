require 'application_system_test_case'

# Getting in, and being told why you cannot. Both are screens with
# something to say rather than status codes, which is the whole reason
# they were built — so they are read here the way a person reads them.
class SessionsSystemTest < ApplicationSystemTestCase
  # "Sign in required" states the system's condition. This is a place, so
  # it says what to do — and where it leads, which is what turns logging
  # in into getting back to what you were doing.
  test 'asking for a curator page leads to a sign-in that says where it returns to' do
    target = admin_submission_request_path(submission_requests(:biosample))

    visit target

    assert_text 'Curator area'
    assert_text 'Log in to continue'
    assert_text target

    mock_keycloak_auth(users(:bob))
    click_button 'Log in with DDBJ Account'

    assert_current_path target
  end

  test 'the sign-in page offers the submitter view as a way out' do
    visit new_admin_session_path

    assert_link href: WebApp.url_for
  end

  # --- no curator access ---------------------------------------------------

  # A bare 403 tells somebody they are wrong without telling them what to
  # do. Logging in again reaches the same result, so the way forward is
  # the submitter view — and that is what the page leads with.
  test 'a submitter is told what happened, and pointed somewhere they can go' do
    sign_in_as users(:carol)

    assert_text 'no curator access'
    assert_text 'carol'

    assert_link 'Go to my submissions', href: WebApp.url_for
    assert_no_button 'Log in with DDBJ Account'
  end

  test 'a curator is not shown the no-access page' do
    sign_in_as users(:bob)

    assert_no_text 'no curator access'
    assert_text 'My queue'
  end
end
