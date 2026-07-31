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
    assert_match 'Needs action',     response.body
    assert_match 'Not applied yet',  response.body
    assert_match 'Unread messages',  response.body
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
    get admin_root_path, params: {bucket: 'failed'}

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
    patch bulk_update_admin_submissions_path,
          params: {bulk: {return_to: 'my_queue', submission_ids: [submissions(:bioproject).id.to_s], status: 'curating'}}

    assert_redirected_to admin_my_queue_path
  end

  test 'a bulk action started from Needs action returns to the same bucket' do
    patch bulk_update_admin_submissions_path(bucket: 'failed'),
          params: {bulk: {return_to: 'needs_action', submission_ids: [submissions(:bioproject).id.to_s], status: 'curating'}}

    assert_redirected_to admin_root_path(bucket: 'failed')
  end

  test 'the queues require admin auth' do
    sign_in_as users(:carol)

    with_exceptions_app do
      get admin_root_path
    end

    assert_response :forbidden
  end
end
