require 'test_helper'

# Which requests are waiting on a curator, and which of the three
# sections each falls into. The screen's reading of this lives in
# test/system/submission_requests_test.rb; these are the rules underneath.
class MyQueueTest < ActiveSupport::TestCase
  setup do
    @req = submission_requests(:bioproject)
  end

  # A request with something a curator can actually do about it: the
  # submitter has written and nobody has opened the thread.
  def unread_request
    @req.tap {
      it.messages.create!(user: users(:alice), author_role: 'submitter', body: 'still waiting on this')
    }
  end

  def section(key, user = users(:bob))
    MyQueue.new(user).sections.find { it.key == key }
  end

  # A status is never a reason to be here — not the submitter's move
  # (`ready_to_apply`, `validation_failed`), and not ours to fix from a
  # queue either (`application_failed` is a dead job, reported to Sentry
  # and listed under /admin/jobs).
  #
  # But a question is a reason whatever the status says: somebody asking
  # while their file sits unapplied is waiting on an answer, and that is
  # the same failure from the other direction.
  test 'a status is never a reason to be queued, and a question always is' do
    %w[ready_to_apply validation_failed application_failed].each do |status|
      @req.update_columns(status: SubmissionRequest.statuses.fetch(status))

      assert_equal 0, MyQueue.new(users(:bob)).count, "#{status} alone is not curator work"
    end

    unread_request

    assert_equal 1, MyQueue.new(users(:bob)).count,
                 'a submitter who asks while their file waits still needs an answer'
  end

  test 'an assigned request is in Assigned to me' do
    unread_request.assign!(users(:bob))

    assert_includes section(:assigned).scope, @req
  end

  test 'a request someone else owns that I worked on is in I am involved' do
    unread_request.assign!(users(:dave))
    @req.participate!(users(:bob))

    assert_includes section(:involved).scope, @req
  end

  # SQL inequality is NULL for an unassigned row, so the obvious
  # `where.not(assignee_id:)` dropped exactly this case — and since
  # Unclaimed excludes anything with a participant, replying to a
  # submitter made the request vanish from every curator's queue.
  test 'a request I worked on that nobody owns is still in I am involved' do
    unread_request.participate!(users(:bob))

    assert_nil @req.assignee_id
    assert_includes section(:involved).scope, @req
  end

  test 'an untouched, unowned request is in Unclaimed' do
    unread_request

    assert_includes section(:unclaimed).scope, @req
  end

  # Somebody else's work is not this curator's queue.
  test 'a request assigned to another curator I have not touched is in no section' do
    unread_request.assign!(users(:dave))

    MyQueue.new(users(:bob)).sections.each do |s|
      assert_not_includes s.scope, @req, "expected ##{@req.id} not to be in #{s.key}"
    end
  end

  test 'the sections are disjoint, so the badge counts each request once' do
    unread_request.assign!(users(:bob))
    @req.participate!(users(:bob))

    assert_equal 1, MyQueue.new(users(:bob)).count, 'assigned + involved must not double-count'
  end

  # A request the submitter has closed is nobody's work: they have said
  # they are not taking it further. Left in, the queue would go on
  # demanding a reply to an abandoned attempt.
  test 'a request the submitter closed is not curator work' do
    req = submission_requests(:bioproject)
    req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'asked')

    assert_includes MyQueue.needing_curator(users(:bob)), req

    req.close!

    assert_not_includes MyQueue.needing_curator(users(:bob)), req
  end

  # Where a curator got to and whether they want to hear about it are
  # separate facts. Filtering the marker on the subscription too made the
  # two readers of it disagree: the Messages tab said nothing was unread
  # while the queue went on counting it.
  test 'a read marker still counts after unsubscribing' do
    req = submission_requests(:bioproject)
    req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'asked')

    req.unsubscribe!(users(:bob))
    req.mark_read_by!(users(:bob))

    assert_equal 0, req.unread_message_count_for(users(:bob))
    assert_not_includes MyQueue.unread_request_ids(users(:bob)).map(&:submission_request_id), req.id
  end

  # --- the set axis -------------------------------------------------------
  #
  # Sets are the queue's second axis. The numbers behind the two badges
  # and the queue's own total all come from here, and each of them was
  # silently zeroable before these existed.

  def waiting_set(author: users(:alice))
    SubmissionSet.create!(name: 'Deep sea study', owner: users(:alice)).tap {
      it.messages.create!(user: author, author_role: :member, body: 'Are these one submission or two?')
    }
  end

  test 'a set with an unanswered question is in the queue, and its count is the badge' do
    set = waiting_set

    assert_equal [set], MyQueue.new(users(:bob)).sets.to_a
    assert_equal 1,     MyQueue.new(users(:bob)).set_count
  end

  test 'the total counts both axes' do
    unread_request
    waiting_set

    assert_equal 2, MyQueue.new(users(:bob)).count, 'one request and one set'
  end

  # Answering is the work, so it settles the set for every curator.
  test 'a colleague answering takes it out of everybody queue' do
    set = waiting_set

    set.messages.create!(user: users(:dave), author_role: :curator, body: 'Two.')

    assert_empty MyQueue.new(users(:bob)).sets.to_a
    assert_empty MyQueue.new(users(:dave)).sets.to_a
  end

  # Reading is not answering, and it speaks for nobody else.
  test 'marking read clears one curator and leaves the others' do
    set     = waiting_set
    message = set.messages.last

    set.mark_read_by!(users(:bob), as: :curator, through: message.id)

    assert_empty MyQueue.new(users(:bob)).sets.to_a
    assert_equal [set], MyQueue.new(users(:dave)).sets.to_a
  end

  # The marker never moves backwards: a stale tab rendered when more was
  # unread would otherwise resurrect everything already dealt with.
  test 'a stale mark-read does not move the marker back' do
    set   = waiting_set
    first = set.messages.last

    second = set.messages.create!(user: users(:alice), author_role: :member, body: 'And another thing')

    set.mark_read_by!(users(:bob), as: :curator, through: second.id)
    set.mark_read_by!(users(:bob), as: :curator, through: first.id)

    assert_empty MyQueue.new(users(:bob)).sets.to_a, 'the older press must not undo the newer one'
  end

  # `through` bounds what a press can discharge to what was on screen.
  test 'a message that landed after the page was drawn is not discharged by it' do
    set  = waiting_set
    seen = set.messages.last

    set.messages.create!(user: users(:alice), author_role: :member, body: 'One more')
    set.mark_read_by!(users(:bob), as: :curator, through: seen.id)

    assert_equal [set], MyQueue.new(users(:bob)).sets.to_a
  end

  # Which side somebody acts from is the screen they pressed, not what
  # their account is: a curator can be on a set's roster like anyone else.
  test 'a curator who is also a member keeps two markers' do
    set        = waiting_set
    membership = set.members.create!(user: users(:bob), invited_by: users(:alice), joined_at: Time.current)

    set.mark_read_by!(users(:bob), as: :member, through: set.messages.last.id)

    assert_not_nil membership.reload.last_read_at, 'the member side is what a press on the member screen marks'
    assert_equal [set], MyQueue.new(users(:bob)).sets.to_a,
                 'and it must not discharge a curator queue entry they never saw as a curator'

    set.mark_read_by!(users(:bob), as: :curator, through: set.messages.last.id)

    assert_empty MyQueue.new(users(:bob)).sets.to_a
  end

  test 'the oldest question comes first' do
    recent = waiting_set
    older  = SubmissionSet.create!(name: 'Asked last week', owner: users(:alice))

    older.messages.create!(user: users(:alice), author_role: :member, body: 'Still waiting', created_at: 7.days.ago)
    older.touch

    assert_equal [older, recent], MyQueue.new(users(:bob)).sets.to_a
  end
end
