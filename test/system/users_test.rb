require 'application_system_test_case'

class UsersSystemTest < ApplicationSystemTestCase
  ALICE = {uid: 'alice', full_name: 'Alice Liddell', email: 'alice@example.com', organization: 'Wonderland', account_type_number: 'general'}.freeze
  CAROL = {uid: 'carol', full_name: 'Carol King',    email: 'carol@example.com', organization: 'Music',      account_type_number: 'general'}.freeze

  setup do
    sign_in_as users(:bob)
  end

  # An unchecked box submits nothing, and "nothing" has to mean "first
  # visit, default on" — so without a hidden partner field the filter
  # could be turned on and never off, and every account that had never
  # submitted was unreachable. Posting `submitted: ''` directly, which is
  # what the integration test did, tests a request no browser makes.
  test 'the "has submitted before" filter can be turned off' do
    # The page's lookup covers exactly the rows it is about to render, so
    # each side of the toggle asks for a different set.
    stub_cloakman_lookup [ALICE],        uids: %w[alice]
    stub_cloakman_lookup [ALICE, CAROL], uids: %w[alice carol]

    visit admin_users_path

    assert_text 'Alice Liddell'
    assert_no_text 'Carol King' # carol has never submitted

    uncheck 'Has submitted before'
    click_button 'Search'

    assert_text 'Alice Liddell'
    assert_text 'Carol King'

    check 'Has submitted before'
    click_button 'Search'

    assert_no_text 'Carol King'
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

  test 'a row opens that account and comes back' do
    stub_cloakman_lookup [ALICE]

    visit admin_users_path
    click_link 'alice'

    assert_current_path admin_user_path(uid: 'alice')
    assert_text 'Alice Liddell'

    within '.navbar' do
      click_link 'Users'
    end

    assert_current_path admin_users_path
  end

  test 'notes are saved with the curator who wrote them' do
    stub_cloakman_lookup [ALICE]

    visit admin_user_path(uid: 'alice')

    assert_text 'Never edited.'

    fill_in 'Notes', with: 'Contact goes through kimura.'
    click_button 'Save notes'

    assert_text 'Notes saved.'
    assert_text 'Last edited by bob'
    assert_field 'Notes', with: 'Contact goes through kimura.'
  end
end
