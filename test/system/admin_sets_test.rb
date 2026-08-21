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

    within '[data-test-section="unclaimed"]' do
      assert_text 'Deep sea study'
      assert_text '1 submission, 2 members'

      click_link 'Deep sea study'
    end

    assert_text 'Are these one submission or two?'

    fill_in 'New message to the set', with: 'Two — one per organism.'

    perform_enqueued_jobs do
      click_button 'Send message'
    end

    assert_text 'Message sent to 2 members of this set.'
    assert_text 'Two — one per organism.'

    # Both members hear about it. This is the thing that stops scaling
    # first, and it is deliberate: everybody in the set is party to the
    # conversation.
    #
    # Bcc, not To: the roster shows each member the address they were
    # invited at, and the addresses their accounts carry are not the
    # set's to hand round.
    mail = ActionMailer::Base.deliveries.last

    assert_equal [@alice.email, @carol.email].sort, mail.bcc.sort
    assert_equal ['repo@ddbj.nig.ac.jp'],           mail.to

    visit admin_my_queue_path

    assert_no_selector "[data-test-set='#{@set.id}']"
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

    # Unclaimed is the shared pool: nobody has claimed this, so putting
    # it aside is about this curator's own count on the Sets tab and not
    # about whether anybody else can still find it.
    assert_selector '.navbar', text: 'Sets 0'

    within '[data-test-section="unclaimed"]' do
      assert_text 'Deep sea study'
    end

    # A colleague still has it.
    assert_equal 1, SubmissionSet.needing_curator(users(:dave)).count
  end

  # The list is not a directory: a curator opens it to find the
  # conversations that are waiting.
  test 'the list filters to what is waiting and says so when nothing is' do
    visit admin_sets_path(waiting: 1)

    within '[data-test-empty-state="clear"]' do
      assert_text 'Nothing waiting'
    end

    @set.messages.create!(user: @alice, author_role: :member, body: 'Anyone?')

    visit admin_sets_path(waiting: 1)

    assert_selector "[data-test-set='#{@set.id}']", text: 'Deep sea study'
    assert_text '1 message'
  end

  # The two filters are different questions and combine. A single slot
  # would answer "which of the ones I follow still need me?" with the
  # wrong list rather than say it could not.
  test 'waiting and following narrow together' do
    @set.messages.create!(user: @alice, author_role: :member, body: 'Anyone?')

    followed = SubmissionSet.create!(name: 'Followed but quiet', owner: @alice)
    followed.subscribe! users(:bob)

    visit admin_sets_path(waiting: 1)
    assert_text 'Deep sea study'
    assert_no_text 'Followed but quiet'

    visit admin_sets_path(following: 1)
    assert_text 'Followed but quiet'
    assert_no_text 'Deep sea study'

    visit admin_sets_path(waiting: 1, following: 1)

    within '[data-test-empty-state="filtered"]' do
      assert_text 'waiting on you and followed by you'
    end

    @set.subscribe! users(:bob)

    visit admin_sets_path(waiting: 1, following: 1)
    assert_text 'Deep sea study'
    assert_no_text 'Followed but quiet'
  end

  # A page past the end used to render an empty table under a filter bar
  # counting the rows that are there.
  test 'a page past the end goes back to one that exists' do
    visit admin_sets_path(page: 99)

    assert_no_selector '[data-test-empty-state]'
    assert_text 'Deep sea study'
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

  # The queue's order and the age it prints are the same fact: how long
  # the question has been sitting. `updated_at` says "just now" for a set
  # somebody renamed this morning, which would put a five-day-old
  # question at the back under a heading promising the opposite.
  test 'the queue is ordered by how long the question has been sitting' do
    old_set = SubmissionSet.create!(name: 'Asked last week', owner: @alice)
    old_set.messages.create!(user: @alice, author_role: :member, body: 'Still waiting', created_at: 7.days.ago)
    old_set.update!(name: 'Asked last week, renamed just now')

    @set.messages.create!(user: @alice, author_role: :member, body: 'Asked today')

    visit admin_my_queue_path

    within '[data-test-section="unclaimed"]' do
      names = all('[data-test-set] a.fw-semibold').map(&:text)

      assert_equal ['Asked last week, renamed just now', 'Deep sea study'], names
      assert_text 'waiting 7d ago'
    end
  end

  # Claiming the conversation. Without it a waiting set sits in every
  # curator's queue until somebody answers, which is the "visible to
  # everyone, owned by nobody" the three sections exist to fix.
  test 'a curator takes a set conversation on, and gives it back' do
    @set.messages.create!(user: @alice, author_role: :member, body: 'Anyone?')

    visit admin_my_queue_path

    within '[data-test-section="unclaimed"]' do
      click_button 'Assign to me'
    end

    assert_text 'Answering: bob'

    visit admin_my_queue_path

    within '[data-test-section="assigned"]' do
      assert_text 'Deep sea study'
    end

    # And a colleague no longer sees it as theirs to pick up.
    assert_empty MyQueue.new(users(:dave)).sections.flat_map { it.set_conversations.to_a }

    visit admin_set_path(@set)
    click_button 'Release'

    assert_text 'Nobody is answering this set'

    visit admin_my_queue_path

    within '[data-test-section="unclaimed"]' do
      assert_text 'Deep sea study'
    end
  end

  # Somebody else holding it is not a wall — the roster is small and the
  # coordination is human — but it has to be visible that it was theirs.
  test 'a set somebody else holds says so, and can be taken over' do
    @set.messages.create!(user: @alice, author_role: :member, body: 'Anyone?')
    @set.assign! users(:dave)

    visit admin_set_path(@set)

    within '[data-test-answering]' do
      assert_text 'dave'
    end

    click_button 'Take over'

    assert_text 'Answering: bob'
  end

  # Bringing a colleague in. Without it the only way is to tell them out
  # of band, and then the thread stops being the record of who was asked.
  test 'a curator copies a colleague in, and it says so on the message' do
    @set.messages.create!(user: @alice, author_role: :member, body: 'Anyone?')

    visit admin_set_path(@set)

    check 'dave'
    fill_in 'New message to the set', with: 'Looping dave in.'

    perform_enqueued_jobs do
      click_button 'Send message'
    end

    assert_text 'dave copied in'
    assert_text 'copied in dave'

    # Following from here on is the whole of what copying somebody in
    # does — plus being told now, because a set with nothing unanswered
    # says nothing in their queue.
    assert @set.following?(users(:dave))

    copied = ActionMailer::Base.deliveries.find { it.subject.to_s.include?('copied you in') }

    assert_not_nil copied
    assert_equal [users(:dave).email], copied.to
  end

  # Somebody already following is greyed rather than offered: there is
  # nothing a tick could mean for them.
  test 'a colleague who already follows the set is not offered again' do
    @set.subscribe! users(:dave)

    visit admin_set_path(@set)

    assert_selector "input#cc_#{users(:dave).id}[disabled]"
  end

  # A curator opening a set is looking at what was said recently. The
  # whole of a three-year conversation is a link away, not the default.
  test 'a long thread renders its newest end, and offers the rest' do
    messages = Array.new(MessageThreadPaging::PER_PAGE + 2) {
      @set.messages.create!(user: @alice, author_role: :member, body: "message #{it}")
    }

    visit admin_set_path(@set)

    assert_text messages.last.body
    assert_no_text messages.first.body

    click_link "Show all #{messages.size} messages"

    assert_text messages.first.body
    assert_text messages.last.body
  end

  # Who is already curating what is in the set. This is what decides
  # whether a set-wide question is the reader's to answer, and it is the
  # one fact neither the set nor the thread carries.
  test 'the queue row says who holds the submissions in the set' do
    @set.messages.create!(user: @alice, author_role: :member, body: 'Anyone?')

    # Three submissions, split: one this curator's, one a colleague's,
    # one nobody's.
    @set.inclusions.create!(submission_request: submission_requests(:biosample), added_by: @alice)
    @set.inclusions.create!(submission_request: submission_requests(:st26), added_by: @alice)

    # `update_columns`: the fixtures carry no uploaded record, and the
    # attachment validation is not what this is about.
    submission_requests(:bioproject).update_columns(assignee_id: users(:bob).id)
    submission_requests(:biosample).update_columns(assignee_id: users(:dave).id)

    visit admin_my_queue_path

    within '[data-test-section="unclaimed"]' do
      assert_text '3 submissions, 2 members — 1 yours, 1 dave, 1 unassigned'
    end
  end

  # A set nobody has been assigned any of is still a real answer, and
  # different from one that is half yours.
  test 'a set nobody is curating says so' do
    @set.messages.create!(user: @alice, author_role: :member, body: 'Anyone?')

    visit admin_my_queue_path

    within '[data-test-section="unclaimed"]' do
      assert_text '1 unassigned'
      assert_no_text 'yours'
    end
  end

  # An attachment control a label does not name cannot be reached by a
  # screen reader or by a test.
  test 'the file control on the curator form is named' do
    visit admin_set_path(@set)

    assert_selector 'label', text: 'Attach files'
    assert_equal 'files_', find('label', text: 'Attach files')[:for]
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
