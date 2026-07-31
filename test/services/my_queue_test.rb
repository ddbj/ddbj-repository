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
end
