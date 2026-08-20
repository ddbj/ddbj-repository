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

  test 'adding answers with what happened' do
    assert_difference 'SubmissionSetInclusion.count', 1 do
      post set_submissions_path(@set),
           params:  {submission_request_ids: [@submission_request.id]}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 200
    assert_equal({'added' => 1, 'already_in_set' => 0}, response.parsed_body)

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
           params:  {submission_request_ids: [carols.id]}.to_json,
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
           params:  {submission_request_ids: [@submission_request.id]}.to_json,
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

  # Ten checkboxes where three are already there is an ordinary press,
  # not a failure. Refusing the lot — which is what the unique index does
  # on its own — would make the submitter work out which three and try
  # again without them.
  test 'adding several counts the ones that were already there rather than refusing' do
    others = 2.times.map {
      @alice.submission_requests.create!(db: 'bioproject', status: :applied, migration_run_id: SecureRandom.uuid)
    }

    @set.inclusions.create!(submission_request: @submission_request, added_by: @alice)

    ids = [@submission_request, *others].map(&:id)

    assert_difference 'SubmissionSetInclusion.count', 2 do
      post set_submissions_path(@set), params: {submission_request_ids: ids}.to_json, headers: JSON_HEADERS
    end

    assert_conform_schema 200
    assert_equal({'added' => 2, 'already_in_set' => 1}, response.parsed_body)
  end

  test 'adding a list where every one is already there is not an error' do
    @set.inclusions.create!(submission_request: @submission_request, added_by: @alice)

    assert_no_difference 'SubmissionSetInclusion.count' do
      post set_submissions_path(@set),
           params:  {submission_request_ids: [@submission_request.id]}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 200
    assert_equal({'added' => 0, 'already_in_set' => 1}, response.parsed_body)
  end

  # Silently adding fewer than they asked for is the worse answer: the
  # screen would report a number nobody can account for.
  test 'one id you do not own refuses the whole list' do
    theirs = @carol.submission_requests.create!(db: 'bioproject', status: :applied, migration_run_id: SecureRandom.uuid)

    assert_no_difference 'SubmissionSetInclusion.count' do
      with_exceptions_app do
        post set_submissions_path(@set),
             params:  {submission_request_ids: [@submission_request.id, theirs.id]}.to_json,
             headers: JSON_HEADERS
      end
    end

    assert_conform_schema 404
  end

  # Both of these are requests the contract already forbids (`minItems`
  # and `maxItems`), so they are asserted on the status rather than
  # against the schema — the point is that the server guards them too
  # instead of trusting a client to have read it.
  test 'an empty list, and more than a screenful, are both refused' do
    with_exceptions_app do
      post set_submissions_path(@set), params: {submission_request_ids: []}.to_json, headers: JSON_HEADERS
    end

    assert_response :unprocessable_content
    assert_equal 'No submissions were named.', response.parsed_body['error']

    with_exceptions_app do
      post set_submissions_path(@set),
           params:  {submission_request_ids: (1..(SetSubmissionsController::MAX_PER_CALL + 1)).to_a}.to_json,
           headers: JSON_HEADERS
    end

    assert_response :unprocessable_content
    assert_match(/Too many at once/, response.parsed_body['error'])
  end

  test 'the same id twice in one list counts once' do
    id = @submission_request.id

    assert_difference 'SubmissionSetInclusion.count', 1 do
      post set_submissions_path(@set), params: {submission_request_ids: [id, id]}.to_json, headers: JSON_HEADERS
    end

    assert_equal({'added' => 1, 'already_in_set' => 0}, response.parsed_body)
  end

  # A malformed body is a client mistake this endpoint has words for. It
  # used to reach `to_i` and come back as a 500 and a Sentry issue.
  test 'a list of things that are not ids is refused rather than crashing' do
    [[{'a' => 1}], [[1]], [true]].each do |bad|
      with_exceptions_app do
        post set_submissions_path(@set), params: {submission_request_ids: bad}.to_json, headers: JSON_HEADERS
      end

      assert_response :unprocessable_content
      assert_equal 'Submission ids must be numbers.', response.parsed_body['error']
    end
  end

  # The cap bounds what the contract bounds — the array as submitted, not
  # the deduplicated one. Otherwise a body the schema refuses is accepted
  # here.
  test 'the cap counts what was sent, not what was left after removing duplicates' do
    over = Array.new(SetSubmissionsController::MAX_PER_CALL + 1) { @submission_request.id }

    with_exceptions_app do
      post set_submissions_path(@set), params: {submission_request_ids: over}.to_json, headers: JSON_HEADERS
    end

    assert_response :unprocessable_content
    assert_match(/Too many at once/, response.parsed_body['error'])
  end
end
