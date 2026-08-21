require 'application_system_test_case'

# The curator's side of a set's conversation: finding one that is
# waiting, answering it, and what answering does to the queue.
#
# The rules it holds to are the request thread's, one axis over —
# answering settles the thread for every curator, reading settles it only
# for the one who read it, and posting follows the set from then on.
class AdminSetsSystemTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:bob)

    @alice = users(:alice)

    # Given an address on purpose: the fixture has none, and a member we
    # cannot reach is dropped from the mail rather than failing it — so
    # without this the "everyone in the set hears about it" assertion
    # below would pass for the wrong reason.
    @carol = users(:carol)
    @carol.update!(email: 'carol@example.com')

    @set = SubmissionSet.create!(name: 'Deep sea study', owner: @alice)
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)
    @set.inclusions.create!(submission_request: submission_requests(:bioproject), added_by: @alice)
  end

  test 'a set waiting for an answer reaches the queue, and answering takes it out' do
    @set.messages.create!(user: @alice, author_role: :member, body: 'Are these one submission or two?')

    visit admin_my_queue_path

    within '[data-test-section="sets"]' do
      assert_text 'Deep sea study'
      assert_text '1 submission, 2 members'

      click_link 'Deep sea study'
    end

    assert_text 'Are these one submission or two?'

    fill_in 'New message to the set', with: 'Two — one per organism.'

    perform_enqueued_jobs do
      click_button 'Send message'
    end

    assert_text 'Message sent to the 2 members of this set.'
    assert_text 'Two — one per organism.'

    # Both members hear about it. This is the thing that stops scaling
    # first, and it is deliberate: everybody in the set is party to the
    # conversation.
    assert_equal [@alice.email, @carol.email].sort, ActionMailer::Base.deliveries.last.to.sort

    visit admin_my_queue_path

    assert_no_selector '[data-test-section="sets"]'
  end

  # Reading is not answering. A curator who has looked and decided there
  # is nothing to say needs it out of their queue without it leaving
  # everyone else's.
  test 'marking read clears this curator and nobody else' do
    @set.messages.create!(user: @alice, author_role: :member, body: 'No reply needed, just a note.')

    visit admin_set_path(@set)

    click_button 'Mark 1 message as read'

    assert_text 'Marked as read.'

    visit admin_my_queue_path
    assert_no_selector '[data-test-section="sets"]'

    # A colleague still has it.
    assert_equal 1, SubmissionSet.needing_curator(users(:dave)).count
  end

  # The list is not a directory: a curator opens it to find the
  # conversations that are waiting.
  test 'the list filters to what is waiting and says so when nothing is' do
    visit admin_sets_path(filter: 'waiting')

    within '[data-test-empty-state="clear"]' do
      assert_text 'Nothing waiting'
    end

    @set.messages.create!(user: @alice, author_role: :member, body: 'Anyone?')

    visit admin_sets_path(filter: 'waiting')

    assert_selector "[data-test-set='#{@set.id}']", text: 'Deep sea study'
    assert_text '1 message'
  end

  # Posting follows it — including for a curator who had stopped, since
  # stepping back in is stepping back in.
  test 'answering follows the set' do
    @set.messages.create!(user: @alice, author_role: :member, body: 'Anyone?')

    visit admin_set_path(@set)

    assert_button 'Follow'

    fill_in 'New message to the set', with: 'Looking now.'
    click_button 'Send message'

    assert_button 'Unfollow'
  end

  # Both screens that list sets order by when the set was last touched,
  # and the conversation is the only thing that touches most of them.
  test 'a set sorts by its conversation, not by when it was renamed' do
    quiet = SubmissionSet.create!(name: 'Renamed yesterday', owner: @alice)
    quiet.update!(name: 'Renamed just now')

    @set.messages.create!(user: @alice, author_role: :member, body: 'Anyone?')

    visit admin_sets_path

    names = all('tbody tr td:first-child').map(&:text)

    assert_equal ['Deep sea study', 'Renamed just now'], names.first(2)
  end

  # The roster is who a message here reaches, so it belongs on the screen
  # that sends one — and the submissions are how a curator gets from the
  # conversation to the work.
  test 'the thread names who is in the set and what is in it' do
    visit admin_set_path(@set)

    assert_text @alice.uid
    assert_text @carol.uid
    assert_link "##{submission_requests(:bioproject).id}"
  end
end
