require 'application_system_test_case'

# Looking a person up: the segments, the search, and what their page
# says. The endpoints' own rules — 404s, 403s, the proxy-login handoff —
# are test/integration/admin/users_test.rb.
class UsersSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)
  end

  # --- segments ------------------------------------------------------------

  # "Has submitted before" is about active submitters, so it does not
  # narrow Staff — curators rarely submit anything, and with the filter
  # defaulting to on the segment came up empty next to a badge counting
  # every one of them.
  test 'the segments switch which population is being looked at' do
    stub_cloakman_lookup [cloakman_profile(:alice)],                        uids: %w[alice]
    stub_cloakman_lookup [cloakman_profile(:bob), cloakman_profile(:dave)], uids: %w[bob dave]

    visit admin_users_path

    assert_text    'Alice Liddell'
    assert_no_text 'Bob Builder'

    click_link 'Staff'

    assert_text    'Bob Builder'
    assert_text    'Dave Curator'
    assert_no_text 'Alice Liddell'
  end

  # An unchecked box submits nothing, and "nothing" has to mean "first
  # visit, default on" — so without a hidden partner field the filter
  # could be turned on and never off, and every account that had never
  # submitted was unreachable. Posting `submitted: ''` directly, which is
  # what the integration test did, tests a request no browser makes.
  test 'the "has submitted before" filter can be turned off' do
    # The page's lookup covers exactly the rows it is about to render, so
    # each side of the toggle asks for a different set.
    stub_cloakman_lookup [cloakman_profile(:alice)], uids: %w[alice]
    stub_cloakman_lookup [cloakman_profile(:alice), cloakman_profile(:carol)], uids: %w[alice carol]

    visit admin_users_path

    assert_text 'Alice Liddell'
    assert_no_text 'Carol King' # carol has never submitted

    uncheck 'Has submitted before'
    click_button 'Search'

    assert_text 'Alice Liddell'
    assert_text 'Carol King'

    check 'Has submitted before'
    click_button 'Search'

    assert_text 'Alice Liddell' # the list narrowed, rather than emptied
    assert_no_text 'Carol King'
  end

  # --- search --------------------------------------------------------------

  test 'searching by uid works without DDBJ Account answering' do
    stub_cloakman_search 'ali', []
    stub_cloakman_lookup [cloakman_profile(:alice)], uids: %w[alice]

    visit admin_users_path
    fill_in 'Search accounts', with: 'ali'
    click_button 'Search'

    assert_text 'Alice Liddell'
  end

  test 'searching by organization widens to what DDBJ Account knows' do
    stub_cloakman_search 'Wonderland', [
      cloakman_profile(:alice),
      # Known to DDBJ Account but never registered here — it has no
      # submissions and no page to open, so it is not a result.
      {uid: 'alicia', full_name: 'Alicia Keys', email: 'alicia@example.com', organization: 'Wonderland', account_type_number: 'general'}
    ]
    stub_cloakman_lookup [cloakman_profile(:alice)], uids: %w[alice]

    visit admin_users_path
    fill_in 'Search accounts', with: 'Wonderland'
    click_button 'Search'

    assert_text    'Alice Liddell'
    assert_no_text 'Alicia Keys'
  end

  # The old code searched DDBJ Account and then intersected the result
  # with the first 100 uids in alphabetical order, so anyone past that
  # point was unfindable — and nothing on the screen said so.
  test 'an account past the first page is still findable' do
    zed     = User.create!(uid: 'zed', api_key: 'test_api_key_zed')
    request = SubmissionRequest.new(user: zed, db: 'st26')
    attach_ddbj_record(request)
    request.save!

    stub_cloakman_search 'zed', []
    stub_cloakman_lookup [cloakman_profile(:alice)], uids: %w[alice zed] # the unfiltered first visit
    stub_cloakman_lookup [], uids: %w[zed]

    visit admin_users_path
    fill_in 'Search accounts', with: 'zed'
    click_button 'Search'

    assert_text 'zed'
  end

  # A row whose profile could not be fetched used to be dropped, so an
  # account that exists looked like one that does not.
  test 'an account whose profile cannot be fetched is still listed' do
    stub_cloakman_lookup [], uids: %w[alice]

    visit admin_users_path

    assert_text 'alice'
    assert_text 'Profile unavailable'
    assert_text '(local copy)'
  end

  # --- the detail ----------------------------------------------------------

  test 'a row opens that account and comes back' do
    stub_cloakman_lookup [cloakman_profile(:alice)]

    visit admin_users_path
    click_link 'alice'

    assert_current_path admin_user_path(uid: 'alice')
    assert_text 'Alice Liddell'

    within '.navbar' do
      click_link 'Users'
    end

    assert_current_path admin_users_path
  end

  # The card used to be a count pointing at the ledger, so "how is this
  # person doing" always cost a detour.
  test 'the detail lists recent requests and leads to one of them' do
    stub_cloakman_lookup [cloakman_profile(:alice)]

    request = users(:alice).submission_requests.order(updated_at: :desc).first

    visit admin_user_path(uid: 'alice')

    assert_text 'Recent requests'

    click_link "##{request.id}"

    assert_current_path admin_submission_request_path(request)
  end

  # What DDBJ Account owns is separated from what we do and labelled with
  # its source, so it is obvious which of these a curator could change.
  test 'the account facts say where they come from, in words rather than a code' do
    stub_cloakman_lookup [cloakman_profile(:alice).merge(account_type_number: 'nbdc')]

    visit admin_user_path(uid: 'alice')

    assert_text 'Submitter'
    assert_text 'NBDC (type 2)'
    assert_text 'Profile source'
    assert_text 'cannot be edited here'
  end

  # Acting as somebody else writes to their record under their name, so
  # what happens is said before it is offered.
  test 'proxy login explains itself before offering the button' do
    stub_cloakman_lookup [cloakman_profile(:alice)]

    visit admin_user_path(uid: 'alice')

    assert_text 'proxy action by you'
    assert_button 'Start proxy session'
  end

  test 'notes are saved with the curator who wrote them' do
    stub_cloakman_lookup [cloakman_profile(:alice)]

    visit admin_user_path(uid: 'alice')

    assert_text 'Never edited.'

    fill_in 'Notes', with: 'Contact goes through kimura.'
    click_button 'Save notes'

    assert_text 'Notes saved.'
    assert_text 'Last edited by bob'
    assert_field 'Notes', with: 'Contact goes through kimura.'
  end
end
