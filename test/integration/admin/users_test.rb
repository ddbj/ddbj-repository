require 'test_helper'

class AdminUsersTest < ActionDispatch::IntegrationTest
  ALICE_PROFILE = {uid: 'alice', full_name: 'Alice Liddell', email: 'alice@example.com', organization: 'Wonderland',   account_type_number: 'general'}.freeze
  BOB_PROFILE   = {uid: 'bob',   full_name: 'Bob Builder',   email: 'bob@example.com',   organization: 'Construction', account_type_number: 'general'}.freeze
  CAROL_PROFILE = {uid: 'carol', full_name: 'Carol King',    email: 'carol@example.com', organization: 'Music',        account_type_number: 'general'}.freeze
  DAVE_PROFILE  = {uid: 'dave',  full_name: 'Dave Curator',  email: 'dave@example.com',  organization: 'DDBJ',         account_type_number: 'general'}.freeze

  setup do
    sign_in_as users(:bob)
  end

  # --- segments ------------------------------------------------------------

  test 'index defaults to submitters who have submitted before' do
    stub_cloakman_lookup [ALICE_PROFILE]

    get admin_users_path

    assert_response :ok
    assert_match    'alice',         response.body
    assert_match    'Alice Liddell', response.body
    assert_no_match(/\bbob\b/,       response.body[/<tbody>.*<\/tbody>/m].to_s, 'staff are their own segment')
  end

  test 'the staff segment answers "who is a curator" in one click' do
    stub_cloakman_lookup [BOB_PROFILE, DAVE_PROFILE]

    get admin_users_path, params: {segment: 'staff', submitted: ''}

    assert_response :ok
    assert_match    'Bob Builder', response.body
    assert_no_match 'Alice Liddell', response.body
  end

  # The old `include_inactive` checkbox, put the way somebody would say it.
  test 'unticking "has submitted before" widens the segment to every account' do
    stub_cloakman_lookup [ALICE_PROFILE, CAROL_PROFILE]

    get admin_users_path, params: {segment: 'submitters', submitted: ''}

    assert_response :ok
    assert_match 'Alice Liddell', response.body
    assert_match 'Carol King',    response.body, 'carol has never submitted'
  end

  # --- search --------------------------------------------------------------

  test 'search matches a uid prefix without asking DDBJ Account' do
    stub_request(:get, 'http://cloakman.example.com/api/users')
      .with(query: {query: 'ali'})
      .to_return(status: 200, body: [].to_json, headers: {'Content-Type' => 'application/json'})

    stub_cloakman_lookup [ALICE_PROFILE]

    get admin_users_path, params: {q: 'ali'}

    assert_response :ok
    assert_match 'Alice Liddell', response.body
  end

  test 'search widens to name and organization matches from DDBJ Account' do
    stub_request(:get, 'http://cloakman.example.com/api/users')
      .with(query: {query: 'Wonderland'})
      .to_return(
        status:  200,
        body:    [
          ALICE_PROFILE,
          # Known to DDBJ Account but never registered here — it has no
          # submissions and no page to open, so it is not a result.
          {uid: 'alicia', full_name: 'Alicia Keys', email: 'alicia@example.com', organization: 'Wonderland', account_type_number: 'general'}
        ].to_json,
        headers: {'Content-Type' => 'application/json'}
      )

    stub_cloakman_lookup [ALICE_PROFILE]

    get admin_users_path, params: {q: 'Wonderland'}

    assert_response :ok
    assert_match    'Alice Liddell', response.body
    assert_no_match 'Alicia Keys',   response.body
  end

  # The old code searched DDBJ Account and then intersected the result with
  # the first 100 uids in alphabetical order, so anyone past that point was
  # unfindable — and nothing on the screen said so.
  test 'search finds an account that falls outside the first page' do
    zed = User.create!(uid: 'zed', api_key: 'test_api_key_zed')
    request = SubmissionRequest.new(user: zed, db: 'st26')
    attach_ddbj_record(request)
    request.save!

    stub_request(:get, 'http://cloakman.example.com/api/users')
      .with(query: {query: 'zed'})
      .to_return(status: 200, body: [].to_json, headers: {'Content-Type' => 'application/json'})

    stub_cloakman_lookup [], uids: %w[zed]

    get admin_users_path, params: {q: 'zed'}

    assert_response :ok
    assert_match 'zed', response.body
  end

  # --- when DDBJ Account does not answer -----------------------------------

  test 'a row whose profile cannot be fetched is shown, not dropped' do
    stub_cloakman_lookup [], uids: %w[alice]

    get admin_users_path

    assert_response :ok
    assert_match 'alice',                 response.body
    assert_match 'Profile unavailable',   response.body
    assert_match 'alice@example.com',     response.body, 'the local copy of the address still helps'
    assert_match '(local copy)',          response.body
  end

  test 'show renders without a profile rather than 404-ing' do
    stub_cloakman_lookup [], uids: %w[alice]

    get admin_user_path(uid: 'alice')

    assert_response :ok
    assert_match 'Profile unavailable', response.body
  end

  test 'show returns 404 when the user is not registered locally' do
    with_exceptions_app do
      get admin_user_path(uid: 'never-seen')
    end

    assert_response :not_found
  end

  # --- detail --------------------------------------------------------------

  test 'show combines the profile with what this system knows' do
    stub_cloakman_lookup [ALICE_PROFILE]

    get admin_user_path(uid: 'alice')

    assert_response :ok
    assert_match 'Alice Liddell', response.body
    assert_match 'Wonderland',    response.body
    assert_match 'Submitter',     response.body
    assert_match 'DDBJ Account',  response.body
  end

  # The account type arrives as a name from the REST profile and as an
  # integer from the id token. Both read the same on screen, and both
  # carry the code so the question can be taken to DDBJ Account.
  test 'show names the account type and keeps its code' do
    stub_cloakman_lookup [ALICE_PROFILE.merge(account_type_number: 'nbdc')]

    get admin_user_path(uid: 'alice')

    assert_response :ok
    assert_match 'NBDC (type 2)', response.body
  end

  test 'show names an account type that arrived as an integer' do
    stub_cloakman_lookup [ALICE_PROFILE.merge(account_type_number: 3)]

    get admin_user_path(uid: 'alice')

    assert_response :ok
    assert_match 'DDBJ (type 3)', response.body
  end

  # The card used to be a count pointing at the ledger, so "how is this
  # person doing" always cost a detour.
  test 'show lists the recent requests rather than only counting them' do
    stub_cloakman_lookup [ALICE_PROFILE]

    get admin_user_path(uid: 'alice')

    assert_response :ok

    users(:alice).submission_requests.each do |request|
      assert_match admin_submission_request_path(request), response.body
    end
  end

  test 'show explains what a proxy session does before offering it' do
    stub_cloakman_lookup [ALICE_PROFILE]

    get admin_user_path(uid: 'alice')

    assert_response :ok
    assert_match 'Start proxy session',            response.body
    assert_match 'proxy action by you',            response.body
    assert_match admin_user_proxy_login_path(user_uid: 'alice'), response.body
  end

  # --- notes ---------------------------------------------------------------

  test 'show includes the persisted notes' do
    users(:alice).update!(notes: 'Existing note')

    stub_cloakman_lookup [ALICE_PROFILE]

    get admin_user_path(uid: 'alice')

    assert_response :ok
    assert_match 'Existing note', response.body
  end

  # Several curators share the field, so an unattributed note is one
  # nobody can act on.
  test 'saving notes records who wrote them and when' do
    stub_cloakman_lookup [ALICE_PROFILE]

    patch admin_user_path(uid: 'alice'), params: {user: {notes: 'Be careful with this account.'}}

    assert_redirected_to admin_user_path(uid: 'alice')
    assert_equal 'Notes saved.', flash[:notice]

    alice = users(:alice).reload

    assert_equal 'Be careful with this account.', alice.notes
    assert_equal users(:bob),                     alice.notes_updated_by
    assert_not_nil alice.notes_updated_at

    get admin_user_path(uid: 'alice')

    assert_match 'Last edited by bob', response.body
  end

  # --- authorisation -------------------------------------------------------

  test 'update returns 403 for non-admin users' do
    sign_in_as users(:carol)

    with_exceptions_app do
      patch admin_user_path(uid: 'alice'), params: {user: {notes: 'nope'}}
    end

    assert_response :forbidden
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

  test 'proxy_login redirects to the web login with the admin token and proxy target' do
    post admin_user_proxy_login_path(user_uid: 'alice')

    # The web client is JWT-only, so proxy-login hands it the admin's own
    # token plus the proxy target; the web login route then acts as alice.
    assert_redirected_to %r{http://repository\.example\.com:4200/web/auth/callback\?token=.+&proxy_login=alice}
  end
end
