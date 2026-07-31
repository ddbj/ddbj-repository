require 'test_helper'

# The two task-axis landing screens. Needs action is the admin root, so a
# curator arrives at work rather than at a directory of features.
class AdminQueuesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)
  end

  test 'the admin root is Needs action' do
    get admin_root_path

    assert_response :ok
    assert_match 'Needs action',            response.body
    assert_match 'Stuck in our pipeline',   response.body
    assert_match 'Unread messages',         response.body
    assert_match 'Awaiting accession',      response.body
  end

  # The queue is what a curator owes somebody. A request whose next move is
  # the submitter's already says "Action needed" on their own screen, and
  # splitting one responsibility across two people usually means neither
  # takes it.
  test 'requests waiting on the submitter stay out of the queue' do
    ready  = build_request(status: :ready_to_apply)
    broken = build_request(status: :validation_failed)

    assert_equal 0, CurationQueue.count

    get admin_root_path

    assert_response :ok
    assert_no_match(/##{ready.id}\b/,  response.body)
    assert_no_match(/##{broken.id}\b/, response.body)
  end

  test 'a request our own pipeline dropped is in the queue' do
    stuck = build_request(status: :application_failed)

    get admin_root_path, params: {bucket: 'stalled'}

    assert_response :ok
    assert_match "##{stuck.id}", response.body
    assert_equal 1, CurationQueue.count
  end

  # Enqueued and never run: normally transient, but nothing else is
  # watching, and the submitter has no retry.
  test 'a request enqueued for apply but never applied is in the queue' do
    stuck = build_request(status: :waiting_application)
    stuck.update_column(:updated_at, (CurationQueue::STALL_GRACE + 1.minute).ago)

    get admin_root_path, params: {bucket: 'stalled'}

    assert_response :ok
    assert_match "##{stuck.id}", response.body
  end

  # Every ordinary Apply passes through waiting_application. Counting it on
  # arrival would flash each one into the curator's red badge.
  test 'a request that has just been enqueued is not yet stuck' do
    build_request(status: :waiting_application)

    assert_equal 0, CurationQueue.count
  end

  test 'the unread-messages bucket lists requests whose submitter is waiting' do
    waiting = submission_requests(:biosample)
    waiting.messages.create!(user: users(:alice), author_role: 'submitter', body: 'still waiting')

    get admin_root_path, params: {bucket: 'unread_messages'}

    assert_response :ok
    assert_match    "##{waiting.id}",                     response.body
    assert_no_match(/##{submission_requests(:st26).id}\b/, response.body)
  end

  test 'the awaiting-accession bucket lists requests with issuable rows' do
    projects(:primary).update!(accession: nil, status: 'curating')

    get admin_root_path, params: {bucket: 'awaiting_accession'}

    assert_response :ok
    assert_match "##{submission_requests(:bioproject).id}", response.body
  end

  test 'a bucket with nothing in it says so' do
    get admin_root_path, params: {bucket: 'stalled'}

    assert_response :ok
    assert_match 'no action needed', response.body
  end

  test 'the nav badge counts each request once across buckets' do
    projects(:primary).update!(accession: nil, status: 'curating')
    submission_requests(:bioproject).messages.create!(user: users(:alice), author_role: 'submitter', body: 'hi')

    assert_equal 1, CurationQueue.count, 'a request in two buckets must be counted once'
  end

  test 'my queue lists only requests whose curation rows are assigned to me' do
    projects(:primary).update!(assignee: users(:bob))

    get admin_my_queue_path

    assert_response :ok
    assert_match    "##{submission_requests(:bioproject).id}", response.body
    assert_no_match(/##{submission_requests(:biosample).id}\b/, response.body)
  end

  test 'my queue is empty when nothing is assigned' do
    get admin_my_queue_path

    assert_response :ok
    assert_match 'Nothing is assigned to you.', response.body
  end

  test 'a bulk action started from a queue returns to that queue' do
    post bulk_update_admin_submissions_path,
          params: {bulk: {return_to: 'my_queue', submission_ids: [submissions(:bioproject).id.to_s], status: 'curating'}}

    assert_redirected_to admin_my_queue_path
  end

  test 'a bulk action started from Needs action returns to the same bucket' do
    post bulk_update_admin_submissions_path(bucket: 'stalled'),
          params: {bulk: {return_to: 'needs_action', submission_ids: [submissions(:bioproject).id.to_s], status: 'curating'}}

    assert_redirected_to admin_root_path(bucket: 'stalled')
  end

  test 'the queues require admin auth' do
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
end
