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

  test 'index filters by multi-select ?db[]=' do
    get submission_requests_path(db: %w[st26 biosample])

    assert_conform_schema 200

    body = response.parsed_body
    ids  = body.pluck('id')

    assert_not_includes body.pluck('db'), 'bioproject'
    assert_includes     ids, submission_requests(:st26).id
    assert_includes     ids, submission_requests(:biosample).id
    assert_not_includes ids, submission_requests(:bioproject).id
  end

  test 'index filters by multi-select ?status[]=' do
    submission_requests(:bioproject).update_column(:status, SubmissionRequest.statuses.fetch('applied'))

    get submission_requests_path(status: %w[applied])

    assert_conform_schema 200

    ids = response.parsed_body.pluck('id')

    assert_includes     ids, submission_requests(:bioproject).id
    assert_not_includes ids, submission_requests(:st26).id # still waiting_validation
  end

  test 'index filters by ?source_id= (case-insensitive prefix)' do
    submissions(:bioproject).update_columns(source_id: 'PSUB000604')

    get submission_requests_path(source_id: 'psub')

    assert_conform_schema 200

    ids = response.parsed_body.pluck('id')

    assert_includes     ids, submission_requests(:bioproject).id
    assert_not_includes ids, submission_requests(:biosample).id
  end

  test 'index filters by ?accession= across BP project / BS samples / ST.26 accessions' do
    get submission_requests_path(accession: 'PRJDB') # BP Project
    assert_conform_schema 200
    ids = response.parsed_body.pluck('id')
    assert_includes     ids, submission_requests(:bioproject).id
    assert_not_includes ids, submission_requests(:biosample).id

    get submission_requests_path(accession: 'SAMD') # BS Sample
    ids = response.parsed_body.pluck('id')
    assert_includes     ids, submission_requests(:biosample).id
    assert_not_includes ids, submission_requests(:bioproject).id

    get submission_requests_path(accession: 'ACC_') # ST.26 accessions table
    ids = response.parsed_body.pluck('id')
    assert_includes     ids, submission_requests(:st26).id
    assert_not_includes ids, submission_requests(:bioproject).id
  end

  test 'index ignores unknown facet values instead of raising on the enum' do
    # Deliberately out-of-schema input (a crafted direct call) — assert only
    # that the controller drops the values rather than 500-ing on the enum
    # coercion; the response won't conform to the Db/status enums.
    get submission_requests_path(db: %w[bogus], status: %w[nope])

    assert_response :ok
    assert_includes response.parsed_body.pluck('id'), submission_requests(:st26).id
  end

  test 'index includes db on each row' do
    get submission_requests_path

    assert_conform_schema 200

    row = response.parsed_body.find { it['id'] == submission_requests(:biosample).id }

    assert_equal 'biosample', row['db']
  end

  test 'index reports the accession summary per DB (BP project / BS samples / ST.26 accessions)' do
    get submission_requests_path

    assert_conform_schema 200

    body = response.parsed_body
    st26 = body.find { it['id'] == submission_requests(:st26).id }
    bp   = body.find { it['id'] == submission_requests(:bioproject).id }
    bs   = body.find { it['id'] == submission_requests(:biosample).id }

    # ST.26: the accessions table (two rows) — first is the lowest id.
    assert_equal submissions(:st26).accessions.order(:id).first.number, st26['first_accession']
    assert_equal 2, st26['accession_count']

    # BP: the Project's accession.
    assert_equal projects(:primary).accession, bp['first_accession']
    assert_equal 1, bp['accession_count']

    # BS: the sample aggregate (one accessioned sample).
    assert_equal samples(:first).accession, bs['first_accession']
    assert_equal 1, bs['accession_count']
  end

  test 'index reports has_unread_curator_message when an unread curator-authored message exists' do
    submission_requests(:bioproject).messages.create!(
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

  # The detail leads with progress and the conversation, so both are
  # derived server-side rather than left for the client to infer from the
  # ingest status enum.
  test 'show carries the derived progress and the conversation facts' do
    request = submission_requests(:bioproject)

    attach_ddbj_record request
    attach_submission_files request.submission

    get submission_request_path(id: request.id)

    assert_conform_schema 200

    body = response.parsed_body

    assert_equal 'accession_issued', body.dig('progress', 'step'), 'the fixture project carries an accession'
    assert_equal false,              body.dig('progress', 'failed')
    assert_equal 1,                  body.dig('progress', 'row_count')
    assert_equal 0,                  body['unread_curator_message_count']
    assert_nil                       body['last_message_at']
  end

  test 'show counts unread curator messages and dates the thread' do
    request = submission_requests(:bioproject)

    attach_ddbj_record request
    attach_submission_files request.submission

    message = request.messages.create!(user: users(:bob), author_role: 'curator', body: 'a question')

    get submission_request_path(id: request.id)

    assert_conform_schema 200

    body = response.parsed_body

    assert_equal 1, body['unread_curator_message_count']
    assert_equal message.created_at.iso8601, body['last_message_at']
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
