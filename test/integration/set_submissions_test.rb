require 'test_helper'

class SubmissionSetInclusionsTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = {'Content-Type' => 'application/json'}.freeze

  setup do
    @alice = users(:alice)
    @carol = users(:carol)

    default_headers['Authorization'] = "Bearer #{@alice.api_key}"

    @set   = SubmissionSet.create!(name: 'Deep sea study', owner: @alice)
    @submission_request = submission_requests(:bioproject) # owned by :alice
  end

  # 204, not 201: the answer carries no body, and 204 is the status that
  # says so. The web client's fetch layer parses every other status as
  # JSON, so a 201 with an empty body reaches it as a parse error.
  test 'adding says only that it is added' do
    assert_difference 'SubmissionSetInclusion.count', 1 do
      post set_submissions_path(@set),
           params:  {submission: {submission_request_id: @submission_request.id}}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 204

    get set_path(@set)

    assert_conform_schema 200

    body = response.parsed_body

    assert_equal 1, body['submission_count']
    assert_equal [@alice.uid], body['submissions'].map { it['owner_uid'] }
    assert_equal [true],       body['submissions'].map { it['owned'] }
    assert_equal @submission_request.id, body['submissions'].sole['submission']['id']
  end

  test 'somebody else\'s submission is not an id you have' do
    carols = @carol.submission_requests.create!(db: 'bioproject', status: :applied, migration_run_id: SecureRandom.uuid)

    with_exceptions_app do
      post set_submissions_path(@set),
           params:  {submission: {submission_request_id: carols.id}}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 404
  end

  test 'reading through a shared set does not let you hand it on' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)
    @set.inclusions.create!(submission_request: @submission_request, added_by: @alice)

    carols_own = SubmissionSet.create!(name: "Carol's other study", owner: @carol)

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    with_exceptions_app do
      post set_submissions_path(carols_own),
           params:  {submission: {submission_request_id: @submission_request.id}}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 404
  end

  test 'only the submission owner can take it out' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)
    @set.inclusions.create!(submission_request: @submission_request, added_by: @alice)

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    with_exceptions_app do
      delete set_submission_path(@set, @submission_request)
    end

    assert_conform_schema 403
  end

  test 'the owner takes it out' do
    @set.inclusions.create!(submission_request: @submission_request, added_by: @alice)

    delete set_submission_path(@set, @submission_request)

    assert_conform_schema 204
    assert_empty @set.inclusions.reload
  end

  test 'a member sees whose submission it is, but not that a private conversation exists' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)
    @set.inclusions.create!(submission_request: @submission_request, added_by: @alice)

    @submission_request.messages.create!(user: users(:bob), author_role: :curator, body: 'Please check the organism.')

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    get set_path(@set)

    assert_conform_schema 200
    assert_equal 0, response.parsed_body['submissions'].sole['submission']['unread_curator_message_count']
  end

  test 'the owner still sees their own unread count' do
    @set.inclusions.create!(submission_request: @submission_request, added_by: @alice)
    @submission_request.messages.create!(user: users(:bob), author_role: :curator, body: 'Please check the organism.')

    get set_path(@set)

    assert_conform_schema 200
    assert_equal 1, response.parsed_body['submissions'].sole['submission']['unread_curator_message_count']
  end
end
