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

  # The queue is what a curator owes somebody. A request whose next move
  # is the submitter's already says "Action needed" on their own screen,
  # and splitting one responsibility across two people usually means
  # neither takes it.
  test 'requests waiting on the submitter are not waiting on a curator' do
    %i[ready_to_apply validation_failed].each do |status|
      @req.update_columns(status: SubmissionRequest.statuses.fetch(status.to_s))

      assert_equal 0, MyQueue.new(users(:bob)).count, "#{status} is the submitter's move"
    end
  end

  # A dead background job is reported to Sentry and listed under
  # /admin/jobs. A curator reading a queue cannot fix it, and having it
  # here only taught them to scroll past a section.
  test 'a request our own pipeline dropped is not in the curator queue' do
    @req.update_columns(status: SubmissionRequest.statuses.fetch('application_failed'))

    assert_equal 0, MyQueue.new(users(:bob)).count
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
