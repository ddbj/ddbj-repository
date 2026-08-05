require 'test_helper'

# The db-scoped API, kept alive for the clients that still address it.
#
# `submission-bulk-st26` feeds production through `/api/st26/...` from six
# places, and it cannot be redeployed in step with this server. Every one
# of those calls is exercised here, in the shape the client actually sends
# — in particular a create whose body names no database, because under the
# old routes the path was where the database lived.
#
# These paths are deliberately absent from schema/openapi.yml, so nothing
# here conforms against it. See the deprecated block in config/routes.rb.
class LegacyDbScopeTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"
  end

  test 'create takes the database from the path when the body does not name one' do
    blob = ActiveStorage::Blob.create_and_upload!(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    perform_enqueued_jobs do
      post legacy_submission_requests_path('st26'), params: {
        submission_request: {ddbj_record: blob.signed_id}
      }, as: :json
    end

    assert_response :accepted

    request = SubmissionRequest.find(response.parsed_body['id'])

    assert_equal 'st26', request.db
    assert_equal @user,  request.user
  end

  # A body that does name a database keeps saying what it says: the two
  # disagreeing is a client bug, and rewriting the payload would hide it.
  test 'a database in the body wins over the one in the path' do
    blob = ActiveStorage::Blob.create_and_upload!(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    perform_enqueued_jobs do
      post legacy_submission_requests_path('st26'), params: {
        submission_request: {db: 'biosample', ddbj_record: blob.signed_id}
      }, as: :json
    end

    assert_response :accepted
    assert_equal 'biosample', SubmissionRequest.find(response.parsed_body['id']).db
  end

  test 'index is scoped to the database in the path' do
    get legacy_submission_requests_path('st26')

    assert_response :success

    ids = response.parsed_body.pluck('id')

    assert_includes     ids, submission_requests(:st26).id
    assert_not_includes ids, submission_requests(:biosample).id
  end

  test 'show and status address a request by id' do
    request = submission_requests(:st26)

    get legacy_submission_request_path('st26', request)

    assert_response :success
    assert_equal request.id, response.parsed_body['id']

    get legacy_submission_request_status_path('st26', submission_request_id: request.id)

    assert_response :success
  end

  test 'applying a validated request' do
    request = submission_requests(:st26)

    attach_ddbj_record request
    request.update! status: :ready_to_apply

    Validation.create!(subject: request, progress: :finished, finished_at: Time.current)

    perform_enqueued_jobs do
      post legacy_submission_request_submission_path('st26', submission_request_id: request.id)
    end

    assert_response :no_content
  end

  test 'listing submissions and their accessions' do
    submission = submissions(:st26)

    get legacy_submissions_path('st26')

    assert_response :success
    assert_includes response.parsed_body.pluck('id'), submission.id

    get legacy_submission_accessions_path('st26', submission_id: submission.id)

    assert_response :success
  end

  # The db segment is a fixed list, so a stray path does not fall through
  # to a controller that would then read it as a filter value.
  test 'an unknown database is not routed' do
    get '/api/nonesuch/submission_requests'

    assert_response :not_found
  end
end
