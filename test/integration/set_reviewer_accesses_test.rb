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
    assert_equal 0, body['count']
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
    assert_equal 1, response.parsed_body['count']
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

    get set_reviewer_access_accessions_path(@set)

    assert_conform_schema 200

    shared = response.parsed_body.sole

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

  # "Everything of mine here" is a press, not a list on the wire: the
  # ninety-eight accessions somebody would otherwise write out to leave
  # two off.
  test 'all shares everything of yours in the set' do
    @set.inclusions.create!(submission_request: submission_requests(:biosample), added_by: @alice)

    enable!

    mine = @set.owned_accessions(@alice).pluck(:accession)

    assert_operator mine.size, :>, 1, 'the fixture set has to hold more than one for this to mean anything'

    assert_difference 'ReviewerAccessAccession.count', mine.size do
      post set_reviewer_access_accessions_path(@set),
           params:  {all: true}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 200
    assert_equal mine.size, response.parsed_body['added']

    get set_reviewer_access_accessions_path(@set)

    assert_conform_schema 200
    assert_equal mine.sort, response.parsed_body.pluck('accession').sort
  end

  # The point of ranges: "everything except the last one" is a range that
  # stops before it, rather than ninety-seven numbers written out.
  test 'a range shares whichever of yours fall inside it' do
    @set.inclusions.create!(submission_request: submission_requests(:st26), added_by: @alice)

    enable!

    assert_difference 'ReviewerAccessAccession.count', 1 do
      post set_reviewer_access_accessions_path(@set),
           params:  {accessions: ['ACC_000001-ACC_000001']}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 200
    assert_equal 1, response.parsed_body['added']
    assert_equal ['ACC_000001'], @set.reviewer_access.shared_accessions.pluck(:accession)
  end

  # A filter, not a list: a range wider than what the caller holds shares
  # what it catches and says nothing about the rest.
  test 'a range wider than what you hold is not an error' do
    @set.inclusions.create!(submission_request: submission_requests(:st26), added_by: @alice)

    enable!

    post set_reviewer_access_accessions_path(@set),
         params:  {accessions: ['ACC_000001-ACC_999999']}.to_json,
         headers: JSON_HEADERS

    assert_conform_schema 200
    assert_equal %w[ACC_000001 ACC_000002], @set.reviewer_access.shared_accessions.pluck(:accession).sort
  end

  # The usual cause is a prefix from the wrong database, and hearing about
  # it now is the difference between a typo and a link that quietly
  # carries nothing.
  test 'a range that catches nothing is refused, and named' do
    enable!

    assert_no_difference 'ReviewerAccessAccession.count' do
      with_exceptions_app do
        post set_reviewer_access_accessions_path(@set),
             params:  {accessions: ['SAMD00009000-SAMD00009999']}.to_json,
             headers: JSON_HEADERS
      end
    end

    assert_conform_schema 422
    assert_includes response.parsed_body['error'], 'SAMD00009000-SAMD00009999'
  end

  # Two ranges over the same block is an ordinary paste — the same
  # accessions written twice at different widths. Reporting the second as
  # empty would throw away what the first matched as well.
  test 'overlapping ranges are not reported as empty' do
    @set.inclusions.create!(submission_request: submission_requests(:st26), added_by: @alice)

    enable!

    post set_reviewer_access_accessions_path(@set),
         params:  {accessions: ['ACC_000001-ACC_000002', 'ACC_000001-ACC_000009']}.to_json,
         headers: JSON_HEADERS

    assert_conform_schema 200
    assert_equal 2, response.parsed_body['added']
  end

  # A page number is multiplied into an OFFSET, so one past what bigint
  # holds used to be a 500 rather than an empty page — and on the
  # reviewer's routes, one anybody holding the link could produce.
  test 'a page number nothing can be on is an empty page, not a crash' do
    enable!
    share! 'PRJDB000001'

    get set_reviewer_access_accessions_path(@set), params: {page: '99999999999999999999'}

    assert_conform_schema 200
    assert_empty response.parsed_body
  end

  # Both of these are bodies the contract already forbids, so neither is
  # checked against the schema — the point is that the server guards them
  # too rather than trusting a client to have read it. `all: false` would
  # otherwise have fallen through to the named path and been answered with
  # a sentence about a key the caller did not send.
  test 'only true asks for all of them' do
    enable!

    with_exceptions_app do
      post set_reviewer_access_accessions_path(@set), params: {all: false}.to_json, headers: JSON_HEADERS
    end

    assert_response :unprocessable_content
    assert_includes response.parsed_body['error'], 'accepted value'

    with_exceptions_app do
      post set_reviewer_access_accessions_path(@set),
           params:  {all: true, accessions: ['PRJDB000001']}.to_json,
           headers: JSON_HEADERS
    end

    assert_response :unprocessable_content
    assert_includes response.parsed_body['error'], 'not both'
  end

  # How much of the link is somebody else's is what Revoke has to say
  # before it fires, and it is counted rather than resolved.
  test 'the link says how much of it belongs to other members' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    access = enable!
    access.shared_accessions.create!(accession: 'PRJDB000001', added_by: @alice)
    access.shared_accessions.create!(accession: 'SAMD00000001', added_by: @carol)

    get set_reviewer_access_path(@set)

    assert_conform_schema 200
    assert_equal 2, response.parsed_body['count']
    assert_equal 1, response.parsed_body['others'], "Alice's own is not one of the others"

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    get set_reviewer_access_path(@set)

    assert_conform_schema 200
    assert_equal 1, response.parsed_body['others'], 'and the answer is asked of whoever is reading'
  end

  # More than one page of it, which is the case the ceiling used to make
  # unreachable.
  test 'a link with more than a page on it is walked a page at a time' do
    @set.inclusions.create!(submission_request: submission_requests(:biosample), added_by: @alice)

    Sample.insert_all!(
      Array.new(25) {|i|
        {
          submission_id: submissions(:biosample).id,
          sample_name:   "bulk-#{i}",
          accession:     format('SAMD9%07d', i)
        }
      },
      record_timestamps: true
    )

    enable!

    post set_reviewer_access_accessions_path(@set), params: {all: true}.to_json, headers: JSON_HEADERS

    assert_conform_schema 200
    assert_equal 27, response.parsed_body['added'], 'the project, the fixture sample, and the twenty-five'

    get set_reviewer_access_accessions_path(@set)

    assert_conform_schema 200
    assert_equal 20,  response.parsed_body.size
    assert_equal '2', response.headers['Total-Pages']

    get set_reviewer_access_accessions_path(@set), params: {page: 2}

    assert_conform_schema 200
    assert_equal 7, response.parsed_body.size

    # Ordered by accession across the whole list, not within a page, which
    # is what makes a second page mean anything.
    assert_operator response.parsed_body.first['accession'], :>, 'SAMD00000001'
  end

  test 'the accessions cannot be listed before the link exists' do
    with_exceptions_app { get set_reviewer_access_accessions_path(@set) }

    assert_conform_schema 404
  end

  test 'a token with a hyphen that is not a range is refused as a range' do
    enable!

    with_exceptions_app do
      post set_reviewer_access_accessions_path(@set),
           params:  {accessions: ['PRJDB1-SAMD00000002']}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 422
    assert_includes response.parsed_body['error'], 'Not an accession or a range'
  end

  test 'numbers and ranges can be pasted together' do
    @set.inclusions.create!(submission_request: submission_requests(:st26), added_by: @alice)

    enable!

    post set_reviewer_access_accessions_path(@set),
         params:  {accessions: ['PRJDB000001', 'ACC_000001-ACC_000002']}.to_json,
         headers: JSON_HEADERS

    assert_conform_schema 200
    assert_equal 3, response.parsed_body['added']
  end

  # A range only ever names the caller's own work, so there is nothing on
  # that path that could belong to somebody else.
  test "a range does not reach a colleague's accessions" do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    enable!

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    with_exceptions_app do
      post set_reviewer_access_accessions_path(@set),
           params:  {accessions: ['PRJDB000001-PRJDB000001']}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 422
    assert_empty @set.reviewer_access.shared_accessions
  end

  # The whole reason `all` is safe to have: it is a gesture that resolves
  # now, not a rule that keeps deciding. A submission added afterwards is
  # not on the link, because nobody has said so.
  test 'all does not keep sharing what is added to the set later' do
    enable!

    post set_reviewer_access_accessions_path(@set),
         params:  {all: true}.to_json,
         headers: JSON_HEADERS

    assert_response :ok

    assert_no_difference 'ReviewerAccessAccession.count' do
      @set.inclusions.create!(submission_request: submission_requests(:biosample), added_by: @alice)
    end

    assert_not_includes @set.reviewer_access.shared_accessions.pluck(:accession), samples(:first).accession
  end

  # Only the caller's own, and that is the whole of the ownership check on
  # this path: there is nothing here that could belong to somebody else.
  test "all does not reach a colleague's submission in the same set" do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    enable!

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    post set_reviewer_access_accessions_path(@set),
         params:  {all: true}.to_json,
         headers: JSON_HEADERS

    assert_conform_schema 200

    # Carol can read Alice's submission through the set — that is what
    # being in it means — and `all` still shares none of it.
    assert_equal 0, response.parsed_body['added']
    assert_empty @set.reviewer_access.shared_accessions
  end

  # There is no ceiling on what a link may carry, so nothing may assume
  # the list arrives whole.
  test 'what is on the link is paginated' do
    enable!
    share! 'PRJDB000001'

    get set_reviewer_access_accessions_path(@set)

    assert_conform_schema 200
    assert_equal '1', response.headers['Total-Pages']
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

  # Reading is untouched by the proxy rule: helping somebody with what
  # they submitted means being able to see what they shared. Only the
  # writes above are theirs alone.
  test 'the lists can be read while acting as another account' do
    enable!
    share! 'PRJDB000001'

    default_headers['Authorization']  = "Bearer #{users(:bob).api_key}"
    default_headers['X-Dway-User-Id'] = @alice.uid

    get set_reviewer_access_accessions_path(@set)

    assert_conform_schema 200
    assert_equal ['PRJDB000001'], response.parsed_body.pluck('accession')

    get set_accessions_path(@set)

    assert_conform_schema 200
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
