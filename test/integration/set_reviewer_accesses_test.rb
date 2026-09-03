require 'test_helper'

class SetReviewerAccessesTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = {'Content-Type' => 'application/json'}.freeze

  setup do
    @alice = users(:alice)
    @carol = users(:carol)

    default_headers['Authorization'] = "Bearer #{@alice.api_key}"

    @set = SubmissionSet.create!(name: 'Deep sea study', owner: @alice)
    @set.inclusions.create!(submission_request: submission_requests(:bioproject), added_by: @alice)
  end

  test 'GET show reports disabled when no link exists' do
    get set_reviewer_access_path(@set)

    assert_conform_schema 200
    assert_equal false, response.parsed_body['enabled']
  end

  test 'POST enables the link and answers with the URL, the expiry and an empty list' do
    assert_difference 'ReviewerAccess.count', 1 do
      post set_reviewer_access_path(@set),
           params:  {reviewer_access: {expires_at: 1.week.from_now.iso8601}}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 201

    body = response.parsed_body

    assert_equal true, body['enabled']
    assert_match %r{/web/reviews/.+}, body['url']
    assert_not_nil body['expires_at']
    assert_empty   body['accessions']
  end

  # Any member, not only the owner: a collaboration is not organised
  # around whoever pressed New first, and a link nobody but one person can
  # revoke is worse than one anybody can.
  test 'any member can enable and revoke the link' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    post set_reviewer_access_path(@set),
         params:  {reviewer_access: {expires_at: 1.week.from_now.iso8601}}.to_json,
         headers: JSON_HEADERS

    assert_conform_schema 201

    assert_difference 'ReviewerAccess.count', -1 do
      delete set_reviewer_access_path(@set)
    end

    assert_response :no_content
  end

  test 'POST again mints a fresh URL and leaves what is on the link alone' do
    enable!
    share! 'PRJDB000001'

    was = @set.reviewer_access.token

    post set_reviewer_access_path(@set),
         params:  {reviewer_access: {expires_at: 1.month.from_now.iso8601}}.to_json,
         headers: JSON_HEADERS

    assert_conform_schema 201
    assert_not_includes response.parsed_body['url'], was
    assert_equal ['PRJDB000001'], response.parsed_body['accessions'].pluck('accession')
  end

  test 'POST with a past expires_at is rejected and leaves the existing link intact' do
    existing = enable!

    post set_reviewer_access_path(@set),
         params:  {reviewer_access: {expires_at: 1.day.ago.iso8601}}.to_json,
         headers: JSON_HEADERS

    assert_response :unprocessable_content
    assert_equal existing.token, @set.reload.reviewer_access.token
  end

  test 'DELETE revokes the link and takes what was on it with it' do
    enable!
    share! 'PRJDB000001'

    assert_difference 'ReviewerAccessAccession.count', -1 do
      delete set_reviewer_access_path(@set)
    end

    assert_response :no_content
    assert_nil @set.reload.reviewer_access
  end

  test 'a set you are not in is not a set you can share' do
    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    with_exceptions_app { get set_reviewer_access_path(@set) }

    assert_conform_schema 404
  end

  test 'putting an accession on the link answers with what happened, and it shows up on the link' do
    enable!

    assert_difference 'ReviewerAccessAccession.count', 1 do
      post set_reviewer_access_accessions_path(@set),
           params:  {accessions: ['PRJDB000001']}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 200
    assert_equal({'added' => 1, 'already_shared' => 0}, response.parsed_body)

    get set_reviewer_access_path(@set)

    assert_conform_schema 200

    shared = response.parsed_body['accessions'].sole

    assert_equal 'PRJDB000001',             shared['accession']
    assert_equal 'bioproject',              shared['db']
    assert_equal 'Primary fixture project', shared['name']
    assert_equal @alice.uid,                shared['owner_uid']
    assert_equal true,                      shared['owned']
  end

  # One already there is an ordinary press, not a failure — the unique
  # index would refuse the lot and leave somebody working out which.
  test 'putting one on twice is counted rather than refused' do
    enable!
    share! 'PRJDB000001'

    assert_no_difference 'ReviewerAccessAccession.count' do
      post set_reviewer_access_accessions_path(@set),
           params:  {accessions: ['PRJDB000001']}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 200
    assert_equal({'added' => 0, 'already_shared' => 1}, response.parsed_body)
  end

  test 'an accession that is not in the set is refused, and named' do
    enable!

    assert_no_difference 'ReviewerAccessAccession.count' do
      with_exceptions_app do
        post set_reviewer_access_accessions_path(@set),
             params:  {accessions: %w[PRJDB000001 PRJDB999999]}.to_json,
             headers: JSON_HEADERS
      end
    end

    assert_conform_schema 422
    assert_includes response.parsed_body['error'], 'PRJDB999999'
  end

  # Both of these are requests the contract already forbids (`minItems`,
  # `maxItems`), so neither is checked against the schema — the point is
  # that the server guards them too instead of trusting a client to have
  # read it.
  test 'an empty list, and more than a paper\'s worth, are both refused' do
    enable!

    with_exceptions_app do
      post set_reviewer_access_accessions_path(@set), params: {accessions: []}.to_json, headers: JSON_HEADERS
    end

    assert_response :unprocessable_content
    assert_equal 'No accessions were named.', response.parsed_body['error']

    with_exceptions_app do
      post set_reviewer_access_accessions_path(@set),
           params:  {accessions: Array.new(SetSharedAccessionsController::MAX_PER_CALL + 1) { "PRJDB#{it}" }}.to_json,
           headers: JSON_HEADERS
    end

    assert_response :unprocessable_content
    assert_includes response.parsed_body['error'], 'maximum'
  end

  test 'taking one back off the link' do
    enable!
    share! 'PRJDB000001'

    assert_difference 'ReviewerAccessAccession.count', -1 do
      delete set_reviewer_access_accession_path(@set, 'PRJDB000001')
    end

    assert_response :no_content
  end

  # The other half of the rule the sharing-boundary test states from the
  # adding side: putting a colleague's work on the link is theirs to do,
  # and so is taking it off again.
  test "a colleague cannot take somebody else's accession off the link" do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    enable!
    share! 'PRJDB000001'

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    assert_no_difference 'ReviewerAccessAccession.count' do
      with_exceptions_app { delete set_reviewer_access_accession_path(@set, 'PRJDB000001') }
    end

    assert_conform_schema 403
  end

  # A row whose submission has left the set names nobody the set can see,
  # so anybody may tidy it. Without that it sits on the list for ever.
  test 'an accession that no longer resolves can be taken off by anyone in the set' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    enable!
    share! 'PRJDB000001'

    @set.inclusions.sole.delete # the row, not the callback that tidies after it

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    assert_difference 'ReviewerAccessAccession.count', -1 do
      delete set_reviewer_access_accession_path(@set, 'PRJDB000001')
    end

    assert_response :no_content
  end

  test 'a link that has expired says so, and takes nothing more' do
    access = enable!
    access.update_column(:expires_at, 1.hour.ago)

    get set_reviewer_access_path(@set)

    assert_conform_schema 200
    assert_equal true, response.parsed_body['expired']

    with_exceptions_app do
      post set_reviewer_access_accessions_path(@set),
           params:  {accessions: ['PRJDB000001']}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 422
    assert_includes response.parsed_body['error'], 'expired'
  end

  test 'a link full to its ceiling takes no more' do
    access = enable!

    ReviewerAccessAccession.insert_all!(
      Array.new(ReviewerAccess::MAX_SHARED) {
        {reviewer_access_id: access.id, accession: "FILLER#{it}", added_by_id: @alice.id}
      },
      record_timestamps: true
    )

    with_exceptions_app do
      post set_reviewer_access_accessions_path(@set),
           params:  {accessions: ['PRJDB000001']}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 422
    assert_includes response.parsed_body['error'], ReviewerAccess::MAX_SHARED.to_s

    # And the same ceiling holds for anything else that puts a row here,
    # which is what makes it the link's rule rather than the endpoint's.
    assert_not access.shared_accessions.build(accession: 'PRJDB000001', added_by: @alice).valid?
  end

  test 'a list of things that are not accession numbers is refused' do
    enable!

    with_exceptions_app do
      post set_reviewer_access_accessions_path(@set),
           params:  {accessions: [{}]}.to_json,
           headers: JSON_HEADERS
    end

    assert_response :unprocessable_content
    assert_equal 'Accessions must be strings.', response.parsed_body['error']
  end

  # Acting as somebody else is for helping them with what they submitted.
  # Deciding who outside DDBJ may read their work is not that.
  test 'nothing here can be written while acting as another account' do
    enable!

    default_headers['Authorization']  = "Bearer #{users(:bob).api_key}"
    default_headers['X-Dway-User-Id'] = @alice.uid

    with_exceptions_app do
      post set_reviewer_access_path(@set),
           params:  {reviewer_access: {expires_at: 1.week.from_now.iso8601}}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 403

    with_exceptions_app { delete set_reviewer_access_path(@set) }

    assert_conform_schema 403

    with_exceptions_app do
      post set_reviewer_access_accessions_path(@set),
           params:  {accessions: ['PRJDB000001']}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 403
  end

  test 'a set you are not in is not a set you can write to either' do
    enable!

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    with_exceptions_app do
      post set_reviewer_access_path(@set),
           params:  {reviewer_access: {expires_at: 1.week.from_now.iso8601}}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 404

    with_exceptions_app { delete set_reviewer_access_path(@set) }

    assert_conform_schema 404

    with_exceptions_app do
      post set_reviewer_access_accessions_path(@set),
           params:  {accessions: ['PRJDB000001']}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 404
  end

  test 'the accessions cannot be named before the link exists' do
    with_exceptions_app do
      post set_reviewer_access_accessions_path(@set),
           params:  {accessions: ['PRJDB000001']}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 404
  end

  private

  def enable!
    ReviewerAccess.enable!(@set, created_by: @alice, expires_at: 1.week.from_now)
  end

  def share!(accession)
    @set.reviewer_access.shared_accessions.create!(accession:, added_by: @alice)
  end
end
