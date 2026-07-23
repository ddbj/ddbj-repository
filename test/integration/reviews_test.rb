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

  test 'the reviewer view never exposes messages' do
    @submission_request.messages.create!(user: users(:bob), author_role: :curator, body: 'internal note')

    get review_path(@access.token)

    assert_response :ok
    assert_not_includes response.parsed_body.keys, 'messages'
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
    @submission_request.submission.accessions.create!(number: 'ACC_REVIEW1', entry_id: 'E|1', version: 1)

    get review_accessions_path(@access.token)

    assert_conform_schema 200
    assert_includes response.parsed_body.pluck('number'), 'ACC_REVIEW1'
  end

  test 'accessions 404s for an expired token' do
    @access.update_column(:expires_at, 1.hour.ago)

    get review_accessions_path(@access.token)

    assert_response :not_found
  end
end
