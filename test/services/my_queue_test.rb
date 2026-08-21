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

  # Unclaimed is one question — has anybody claimed this — and having
  # replied is not a claim. The row stays in the pool until somebody
  # takes it, wherever else it also appears.
  test 'a request I worked on that nobody owns is in Unclaimed, not in I am involved' do
    unread_request.subscribe!(users(:bob))

    assert_nil @req.assignee_id
    assert_includes     section(:unclaimed).scope, @req
    assert_not_includes section(:involved).scope,  @req
  end

  test 'an untouched, unowned request is in Unclaimed' do
    unread_request

    assert_includes section(:unclaimed).scope, @req
  end

  # The hole the old rule left: a curator who followed something and
  # then put it aside took it out of their own sections AND out of
  # everybody's pool, leaving a submitter waiting on work that appeared
  # in no queue at all.
  test 'putting an unclaimed request aside does not take it out of the pool' do
    unread_request.subscribe!(users(:bob))
    @req.mark_read_by!(users(:bob), through: @req.messages.last.id)

    assert_includes section(:unclaimed).scope,               @req
    assert_includes section(:unclaimed, users(:dave)).scope, @req
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

  # Sets live in the same three sections as requests: what makes a piece
  # of work this curator's is the same question either way.
  def queued_sets(user = users(:bob))
    MyQueue.new(user).sections.flat_map { it.set_conversations.to_a }
  end

  def section_of(set, user = users(:bob))
    MyQueue.new(user).sections.find { it.set_conversations.exists?(id: set.id) }&.key
  end

  test 'a set with an unanswered question is in the queue, and its count is the badge' do
    set = waiting_set

    assert_equal [set], queued_sets
    assert_equal 1,     MyQueue.new(users(:bob)).set_count
  end

  # The three sections, on the set axis. Claiming is what takes a
  # conversation out of everybody else's queue — which is the whole
  # reason the column exists.
  test 'an unclaimed set is unclaimed for everyone, and claiming moves it' do
    set = waiting_set

    assert_equal :unclaimed, section_of(set)
    assert_equal :unclaimed, section_of(set, users(:dave))

    set.assign! users(:bob)

    assert_equal :assigned, section_of(set)
    assert_nil section_of(set, users(:dave)), 'somebody else holds it and dave has never touched it'
  end

  # Answering follows it, so a colleague who replied to a set somebody
  # else holds keeps seeing it — without owning it.
  test 'a set you follow but do not hold is involved, not assigned' do
    set = waiting_set

    set.assign!    users(:dave)
    set.subscribe! users(:bob)

    assert_equal :involved, section_of(set)
    assert_equal :assigned, section_of(set, users(:dave))
  end

  # Following is not claiming, on this axis either — and a follower who
  # puts it aside must not take it out of the pool with them.
  test 'a set nobody holds stays in the pool however many people follow it' do
    set = waiting_set

    set.subscribe! users(:bob)

    assert_equal :unclaimed, section_of(set)

    set.mark_read_by!(users(:bob), as: :curator, through: set.messages.last.id)

    assert_equal :unclaimed, section_of(set)
    assert_equal :unclaimed, section_of(set, users(:dave))
  end

  # Releasing puts it back where anybody can take it.
  test 'releasing a set makes it unclaimed again' do
    set = waiting_set

    set.assign! users(:bob)
    set.assign! nil

    assert_equal :unclaimed, section_of(set)
  end

  test 'only a curator can be assigned a set' do
    set = waiting_set

    assert_raises(ArgumentError) { set.assign!(users(:alice)) }
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

    assert_empty queued_sets
    assert_empty queued_sets(users(:dave))
  end

  # Reading is not answering, and it speaks for nobody else. Read
  # through `set_count` — the number behind the Sets tab — because that
  # is the per-curator one: the Unclaimed section is deliberately the
  # same for everybody (a colleague putting something aside must not hide
  # it from the pool), which is the request axis's rule too.
  test 'marking read clears one curator and leaves the others' do
    set     = waiting_set
    message = set.messages.last

    set.mark_read_by!(users(:bob), as: :curator, through: message.id)

    assert_equal 0, MyQueue.new(users(:bob)).set_count
    assert_equal 1, MyQueue.new(users(:dave)).set_count
  end

  # Claimed, it is one curator's — and marking it read takes it out of
  # their sections rather than only out of their badge.
  test 'marking an assigned set read takes it out of the queue' do
    set = waiting_set

    set.assign! users(:bob)

    assert_equal [set], queued_sets

    set.mark_read_by!(users(:bob), as: :curator, through: set.messages.last.id)

    assert_empty queued_sets
  end

  # The marker never moves backwards: a stale tab rendered when more was
  # unread would otherwise resurrect everything already dealt with.
  test 'a stale mark-read does not move the marker back' do
    set   = waiting_set
    first = set.messages.last

    second = set.messages.create!(user: users(:alice), author_role: :member, body: 'And another thing')

    set.mark_read_by!(users(:bob), as: :curator, through: second.id)
    set.mark_read_by!(users(:bob), as: :curator, through: first.id)

    assert_equal 0, MyQueue.new(users(:bob)).set_count, 'the older press must not undo the newer one'
  end

  # `through` bounds what a press can discharge to what was on screen.
  test 'a message that landed after the page was drawn is not discharged by it' do
    set  = waiting_set
    seen = set.messages.last

    set.messages.create!(user: users(:alice), author_role: :member, body: 'One more')
    set.mark_read_by!(users(:bob), as: :curator, through: seen.id)

    assert_equal 1, MyQueue.new(users(:bob)).set_count
  end

  # Which side somebody acts from is the screen they pressed, not what
  # their account is: a curator can be on a set's roster like anyone else.
  test 'a curator who is also a member keeps two markers' do
    set        = waiting_set
    membership = set.members.create!(user: users(:bob), invited_by: users(:alice), joined_at: Time.current)

    set.mark_read_by!(users(:bob), as: :member, through: set.messages.last.id)

    assert_not_nil membership.reload.last_read_at, 'the member side is what a press on the member screen marks'
    assert_equal 1, MyQueue.new(users(:bob)).set_count,
                 'and it must not discharge a curator queue entry they never saw as a curator'

    set.mark_read_by!(users(:bob), as: :curator, through: set.messages.last.id)

    assert_equal 0, MyQueue.new(users(:bob)).set_count
  end

  test 'the oldest question comes first' do
    recent = waiting_set
    older  = SubmissionSet.create!(name: 'Asked last week', owner: users(:alice))

    older.messages.create!(user: users(:alice), author_role: :member, body: 'Still waiting', created_at: 7.days.ago)
    older.touch

    assert_equal [older, recent], queued_sets
  end
end
