require 'test_helper'

# My queue is the landing screen: everything waiting on a curator, split
# by that curator's relationship to it, oldest first, with the next move
# on the row.
class AdminQueuesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)
  end

  test 'the admin root shows every section with its criterion' do
    get admin_root_path

    assert_response :ok
    assert_match 'My queue',         response.body
    assert_match 'Assigned to me',   response.body
    assert_match 'I&#39;m involved', response.body
    assert_match 'Unclaimed',        response.body

    # The rule, next to the section — the difference between "assigned"
    # and "involved" is the whole design, so it is written down rather
    # than left to be inferred.
    assert_match 'assignment only changes when someone changes it', response.body
    assert_match 'You replied or edited here',                      response.body
    assert_match 'every curator sees this section identically',     response.body
  end

  # The queue is what a curator owes somebody. A request whose next move is
  # the submitter's already says "Action needed" on their own screen, and
  # splitting one responsibility across two people usually means neither
  # takes it.
  test 'requests waiting on the submitter stay out of the queue' do
    ready  = build_request(status: :ready_to_apply)
    broken = build_request(status: :validation_failed)

    assert_equal 0, MyQueue.new(users(:bob)).count

    get admin_root_path

    assert_response :ok
    assert_no_match(/##{ready.id}\b/,  response.body)
    assert_no_match(/##{broken.id}\b/, response.body)
  end

  # A dead background job is reported to Sentry and listed under
  # /admin/jobs. A curator reading a queue cannot fix it, and having it
  # here only taught them to scroll past a section.
  test 'a request our own pipeline dropped is not in the curator queue' do
    dropped = build_request(status: :application_failed)

    get admin_root_path

    assert_response :ok
    assert_no_match(/##{dropped.id}\b/, response.body)
  end

  # --- the three sections -------------------------------------------------

  test 'a request assigned to me lands in Assigned to me with its reason' do
    request = unread_request
    request.assign!(users(:bob))

    get admin_root_path

    assert_response :ok
    assert_match(/##{request.id}\b/, response.body)
    assert_match '1 unread message', response.body
    assert_match messages_admin_submission_request_path(request), response.body
  end

  # The point of participation: replying keeps a request in your queue
  # without taking it away from whoever owns it.
  test 'a request I replied on but someone else owns lands in I am involved' do
    request = unread_request
    request.assign!(users(:dave))
    request.participate!(users(:bob))

    get admin_root_path

    assert_response :ok
    assert_match(/##{request.id}\b/, response.body)
    assert_match 'assignee dave',    response.body
  end

  # The gap the three sections have to cover between them: a request
  # nobody has claimed that this curator has already replied to. It is not
  # assigned, and it is not unclaimed either — and SQL's `!=` quietly
  # excludes NULL, so it used to fall out of all three.
  test 'a request I replied on that nobody owns is still in my queue' do
    request = unread_request
    request.participate!(users(:bob))

    assert_nil request.assignee_id
    assert_equal 1, MyQueue.new(users(:bob)).count

    get admin_root_path

    assert_response :ok
    assert_match(/##{request.id}\b/, response.body)
  end

  test 'a request nobody owns or has touched lands in Unclaimed with a claim button' do
    request = unread_request

    get admin_root_path

    assert_response :ok
    assert_match(/##{request.id}\b/, response.body)
    assert_match admin_submission_request_assignment_path(request), response.body
  end

  # Somebody else's work is not this curator's queue.
  test 'a request assigned to another curator I have not touched is in no section' do
    request = unread_request
    request.assign!(users(:dave))

    get admin_root_path

    assert_response :ok
    assert_no_match(/##{request.id}\b/, response.body)
  end

  # --- the badge ----------------------------------------------------------

  test 'the nav badge counts each request once' do
    request = unread_request
    request.assign!(users(:bob))
    request.participate!(users(:bob))

    assert_equal 1, MyQueue.new(users(:bob)).count, 'assigned + involved must not double-count'
  end

  test 'my queue says so when nothing is waiting' do
    get admin_root_path

    assert_response :ok
    assert_match 'Nothing is waiting on a curator right now.', response.body
  end

  test 'the queue requires admin auth' do
    sign_in_as users(:carol)

    with_exceptions_app do
      get admin_root_path
    end

    assert_response :forbidden
  end

  private

  def build_request(status:)
    request = SubmissionRequest.new(user: users(:alice), db: 'st26', status:)
    attach_ddbj_record(request)
    request.save!
    request
  end

  # A request with something a curator can actually do about it: the
  # submitter has written and nobody has opened the thread.
  def unread_request
    submission_requests(:bioproject).tap {
      it.messages.create!(user: users(:alice), author_role: 'submitter', body: 'still waiting on this')
    }
  end
end
