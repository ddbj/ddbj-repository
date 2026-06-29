require 'test_helper'

class SubmissionRequestsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"
  end

  test 'index across all dbs' do
    get submission_requests_path

    assert_conform_schema 200

    ids = response.parsed_body.pluck('id')

    assert_includes ids, submission_requests(:st26).id
    assert_includes ids, submission_requests(:bioproject).id
    assert_includes ids, submission_requests(:biosample).id
  end

  test 'index filters by ?db=' do
    get submission_requests_path(db: 'bioproject')

    assert_conform_schema 200

    body = response.parsed_body
    ids  = body.pluck('id')

    assert_equal ['bioproject'], body.pluck('db').uniq
    assert_includes     ids,     submission_requests(:bioproject).id
    assert_not_includes ids,     submission_requests(:st26).id
  end

  test 'index includes db on each row' do
    get submission_requests_path

    assert_conform_schema 200

    row = response.parsed_body.find { it['id'] == submission_requests(:biosample).id }

    assert_equal 'biosample', row['db']
  end

  test 'index reports has_accession when the submission has accessions' do
    get submission_requests_path

    assert_conform_schema 200

    body = response.parsed_body

    row_with_accession    = body.find { it['id'] == submission_requests(:st26).id }
    row_without_accession = body.find { it['id'] == submission_requests(:bioproject).id }

    assert row_with_accession['has_accession']
    assert_not row_without_accession['has_accession']
  end

  test 'index reports has_unread_curator_message when an unread curator-authored message exists' do
    submissions(:bioproject).messages.create!(
      user:        users(:bob),
      author_role: :curator,
      body:        'curator note'
    )

    get submission_requests_path

    assert_conform_schema 200

    body = response.parsed_body
    bp   = body.find { it['id'] == submission_requests(:bioproject).id }
    st26 = body.find { it['id'] == submission_requests(:st26).id }

    assert bp['has_unread_curator_message']
    assert_not st26['has_unread_curator_message']
  end

  test 'show' do
    request = submission_requests(:st26)

    attach_ddbj_record request
    attach_submission_files request.submission

    get submission_request_path(id: request.id)

    assert_conform_schema 200
  end

  test 'create' do
    blob = ActiveStorage::Blob.create_and_upload!(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    perform_enqueued_jobs do
      post submission_requests_path, params: {
        submission_request: {
          db:          'st26',
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

  test 'show returns 404 for another user' do
    sign_in_as_user(users(:bob))

    with_exceptions_app do
      get submission_request_path(id: submission_requests(:st26).id)
    end

    assert_conform_schema 404
  end

  test 'create persists the db from the request body' do
    blob = ActiveStorage::Blob.create_and_upload!(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    perform_enqueued_jobs do
      post submission_requests_path, params: {
        submission_request: {
          db:          'biosample',
          ddbj_record: blob.signed_id
        }
      }, as: :json
    end

    assert_conform_schema 202
    assert_equal 'biosample', SubmissionRequest.find(response.parsed_body['id']).db
  end

  private

  def sign_in_as_user(user)
    default_headers['Authorization'] = "Bearer #{user.api_key}"
  end
end
