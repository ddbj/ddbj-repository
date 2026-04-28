require 'test_helper'

class SubmissionRequestsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"
  end

  test 'index' do
    get submission_requests_path(db: 'st26')

    assert_conform_schema 200
  end

  test 'show' do
    request = submission_requests(:st26)

    attach_ddbj_record request
    attach_submission_files request.submission
    attach_ddbj_record submission_updates(:st26)

    get submission_request_path(db: 'st26', id: request.id)

    assert_conform_schema 200
  end

  test 'create' do
    blob = ActiveStorage::Blob.create_and_upload!(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    perform_enqueued_jobs do
      post submission_requests_path(db: 'st26'), params: {
        submission_request: {
          ddbj_record: blob.signed_id
        }
      }, as: :json
    end

    assert_conform_schema 202

    body = response.parsed_body

    assert_equal 'finished', body.dig('validation', 'progress')
    assert_equal 'valid',    body.dig('validation', 'validity')
    assert_equal [],         body.dig('validation', 'details')
    assert_nil               body['submission']
  end

  test 'index is scoped by db' do
    attach_ddbj_record submission_requests(:bioproject)

    get submission_requests_path(db: 'bioproject')

    assert_conform_schema 200

    ids = response.parsed_body.pluck('id')

    assert_includes     ids, submission_requests(:bioproject).id
    assert_not_includes ids, submission_requests(:st26).id
  end

  test 'show returns 404 across dbs' do
    attach_ddbj_record submission_requests(:st26)

    with_exceptions_app do
      get submission_request_path(db: 'bioproject', id: submission_requests(:st26).id)
    end

    assert_conform_schema 404
  end

  test 'create persists the db from the route' do
    blob = ActiveStorage::Blob.create_and_upload!(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    perform_enqueued_jobs do
      post submission_requests_path(db: 'biosample'), params: {
        submission_request: {
          ddbj_record: blob.signed_id
        }
      }, as: :json
    end

    assert_conform_schema 202
    assert_equal 'biosample', SubmissionRequest.find(response.parsed_body['id']).db
  end
end
