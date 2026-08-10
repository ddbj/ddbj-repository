require 'test_helper'

class ReviewsTest < ActionDispatch::IntegrationTest
  setup do
    @submission_request = submission_requests(:bioproject)

    attach_ddbj_record       @submission_request
    attach_submission_files  @submission_request.submission

    @access = @submission_request.create_reviewer_access!(expires_at: 1.week.from_now)
  end

  # No Authorization header is ever set here — the whole point is access
  # without logging in.

  test 'GET with a valid token returns the request and conforms to schema' do
    get review_path(@access.token)

    assert_conform_schema 200
    assert_equal @submission_request.id, response.parsed_body['id']
  end

  # The endpoint is unauthenticated, so "no messages" has to mean the
  # conversation is invisible — not merely that the bodies are withheld.
  # An unread count or a last-posted timestamp still tells a link holder
  # that a curator asked something, and roughly when.
  test 'the reviewer view never exposes messages, nor that any exist' do
    @submission_request.messages.create!(user: users(:bob), author_role: :curator, body: 'internal note')

    get review_path(@access.token)

    assert_response :ok

    keys = response.parsed_body.keys

    assert_not_includes keys, 'messages'
    assert_not_includes keys, 'unread_curator_message_count'
    assert_not_includes keys, 'last_message_at'
    assert_not_includes response.body, 'internal note'
  end

  # The submitter's own view of the same request does carry them — the
  # difference between the two schemas is the point.
  test 'the submitter view of the same request does carry the conversation facts' do
    @submission_request.messages.create!(user: users(:bob), author_role: :curator, body: 'internal note')

    default_headers['Authorization'] = "Bearer #{@submission_request.user.api_key}"
    get submission_request_path(id: @submission_request.id)

    assert_conform_schema 200
    assert_equal 1, response.parsed_body.fetch('unread_curator_message_count')
    assert_not_nil  response.parsed_body.fetch('last_message_at')
  end

  test 'an expired token 404s' do
    @access.update_column(:expires_at, 1.hour.ago)

    get review_path(@access.token)

    assert_response :not_found
  end

  test 'an unknown token 404s' do
    get review_path('does-not-exist')

    assert_response :not_found
  end

  test 'GET accessions returns the submission accessions' do
    @submission_request.submission.entries.create!(accession: 'ACC_REVIEW1', entry_id: 'E|1', version: 1, locus_date: Date.new(2026, 1, 15))

    get review_accessions_path(@access.token)

    assert_conform_schema 200
    assert_includes response.parsed_body.pluck('accession'), 'ACC_REVIEW1'

    # The share token is unauthenticated, and where DDBJ has got to with an
    # entry is not a reviewer's business — the same reason the message
    # thread is unreachable from here. The submitter's own list of the
    # same entries does carry it, which is what makes this a separate
    # view rather than a flag on one.
    assert_not_includes response.parsed_body.first.keys, 'status'
  end

  test 'accessions 404s for an expired token' do
    @access.update_column(:expires_at, 1.hour.ago)

    get review_accessions_path(@access.token)

    assert_response :not_found
  end
end
