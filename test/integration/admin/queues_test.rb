require 'test_helper'

# Needs action is a queue, not a filtered list: every bucket at once, each
# carrying the rule that put a request in it, oldest first, with the next
# move on the row.
class AdminQueuesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)
  end

  test 'the admin root shows every bucket with its criterion' do
    get admin_root_path

    assert_response :ok
    assert_match 'Needs action',                  response.body
    assert_match 'Stuck in the pipeline',         response.body
    assert_match 'Unread submitter messages',     response.body
    assert_match 'Ready for accession issuance',  response.body

    # The rule, next to the bucket — so the queue's meaning is on screen
    # rather than in a remembered filter combination.
    assert_match 'A background job should have finished by now', response.body
    assert_match 'no curator has opened the thread since',       response.body
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

    get admin_root_path

    assert_response :ok
    assert_match "##{stuck.id}", response.body
    assert_equal 1, CurationQueue.count
  end

  # A machine state says nothing by its presence, only by its persistence.
  test 'a machine state counts only once it has stopped moving' do
    stuck = build_request(status: :waiting_validation)

    assert_equal 0, CurationQueue.count, 'a request still in flight is not stuck'

    stuck.update_column(:updated_at, (CurationQueue::STUCK_GRACE + 1.minute).ago)

    assert_equal 1, CurationQueue.count

    get admin_root_path

    assert_response :ok
    assert_match "##{stuck.id}", response.body
    assert_match 'Check job',    response.body
  end

  test 'the unread-messages bucket quotes the submitter and offers a reply' do
    waiting = submission_requests(:biosample)
    waiting.messages.create!(user: users(:alice), author_role: 'submitter', body: 'still waiting on this')

    get admin_root_path

    assert_response :ok
    assert_match "##{waiting.id}",                                response.body
    assert_match 'still waiting on this',                         response.body
    assert_match messages_admin_submission_request_path(waiting), response.body
  end

  # Work that can be finished without opening the request should not
  # require opening the request.
  test 'the accession bucket counts what is pending and offers to issue it' do
    projects(:primary).update!(accession: nil, status: 'curating')

    get admin_root_path

    assert_response :ok
    assert_match "##{submission_requests(:bioproject).id}",                     response.body
    assert_match '1 of 1 project pending',                                      response.body
    assert_match admin_submission_accession_path(submissions(:bioproject)),     response.body
  end

  test 'an empty bucket says so rather than disappearing' do
    get admin_root_path

    assert_response :ok
    assert_match 'Nothing here.', response.body
  end

  test 'the nav badge counts each request once across buckets' do
    projects(:primary).update!(accession: nil, status: 'curating')
    submission_requests(:bioproject).messages.create!(user: users(:alice), author_role: 'submitter', body: 'hi')

    assert_equal 1, CurationQueue.count, 'a request in two buckets must be counted once'
  end

  # Mine only filters the same queue rather than opening a different
  # screen, so a curator can look up from their own work and back.
  test 'Mine only narrows the queue to the curator own rows' do
    projects(:primary).update!(accession: nil, status: 'curating', assignee: users(:bob))
    samples(:first).update!(accession: nil, status: 'curating')
    samples(:second).update!(accession: nil, status: 'curating')

    get admin_root_path

    assert_match "##{submission_requests(:biosample).id}", response.body

    get admin_root_path(mine: 1)

    assert_response :ok
    assert_match    "##{submission_requests(:bioproject).id}",                  response.body
    assert_no_match(/##{submission_requests(:biosample).id}\b/,                 response.body)
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

  test 'a bulk action started from Needs action keeps the queue scope' do
    post bulk_update_admin_submissions_path(mine: 1),
         params: {bulk: {return_to: 'needs_action', submission_ids: [submissions(:bioproject).id.to_s], status: 'curating'}}

    assert_redirected_to admin_root_path(mine: 1)
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
