require 'test_helper'

class GroupsTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = {'Content-Type' => 'application/json'}.freeze

  setup do
    @alice = users(:alice)
    @carol = users(:carol)

    default_headers['Authorization'] = "Bearer #{@alice.api_key}"

    @set = SubmissionSet.create!(name: 'Deep sea study', owner: @alice)
  end

  test 'index lists the sets you have joined, and not the ones you have only been invited to' do
    SubmissionSet.create!(name: 'Somebody else', owner: @carol).members.create!(email: 'alice@example.com', invited_by: @carol)

    get sets_path

    assert_conform_schema 200
    assert_equal ['Deep sea study'], response.parsed_body.map { it['name'] }
  end

  test 'create makes the creator the owner and the first member' do
    assert_difference 'SubmissionSet.count', 1 do
      post sets_path, params: {set: {name: 'Hot spring metagenome'}}.to_json, headers: JSON_HEADERS
    end

    assert_conform_schema 201

    body = response.parsed_body

    assert_equal 'Hot spring metagenome', body['name']
    assert_equal true,  body['owned']
    assert_equal 1,     body['member_count']
    assert_equal 0,     body['invited_count']
    assert_equal [@alice.uid], body['members'].map { it['uid'] }
  end

  test 'show 404s for a set you are not in' do
    other = SubmissionSet.create!(name: 'Not yours', owner: @carol)

    with_exceptions_app do
      get set_path(other)
    end

    assert_conform_schema 404
  end

  test 'rename is the owner only' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    with_exceptions_app do
      patch set_path(@set), params: {set: {name: 'Renamed'}}.to_json, headers: JSON_HEADERS
    end

    assert_conform_schema 403
    assert_equal 'Deep sea study', @set.reload.name
  end

  test 'delete is refused while anybody else is still in it' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    with_exceptions_app do
      delete set_path(@set)
    end

    assert_conform_schema 422
    assert SubmissionSet.exists?(@set.id)
  end

  test 'delete is refused while a submission is still in it' do
    @set.inclusions.create!(submission_request: submission_requests(:bioproject), added_by: @alice)

    with_exceptions_app do
      delete set_path(@set)
    end

    assert_conform_schema 422
  end

  test 'delete is refused while an invitation nobody has used is still out' do
    @set.members.create!(email: 'newcomer@example.org', invited_by: @alice)

    with_exceptions_app do
      delete set_path(@set)
    end

    assert_conform_schema 422
  end

  test 'delete empties out' do
    delete set_path(@set)

    assert_conform_schema 204
    assert_not SubmissionSet.exists?(@set.id)
  end

  test 'a set you are not in cannot be renamed or deleted either' do
    other = SubmissionSet.create!(name: 'Not yours', owner: @carol)

    with_exceptions_app do
      patch set_path(other), params: {set: {name: 'Renamed'}}.to_json, headers: JSON_HEADERS
    end

    assert_conform_schema 404

    with_exceptions_app { delete set_path(other) }

    assert_conform_schema 404
  end

  test 'a curator acting as somebody else cannot make or unmake their sets' do
    default_headers['Authorization']  = "Bearer #{users(:bob).api_key}"
    default_headers['X-Dway-User-Id'] = @alice.uid

    with_exceptions_app do
      post sets_path, params: {set: {name: 'On their behalf'}}.to_json, headers: JSON_HEADERS
    end

    assert_conform_schema 403

    get sets_path

    assert_conform_schema 200
  end

  # A set has no ceiling on what it holds, so the screen reads a page of
  # it. Without this nothing would notice the day somebody puts three
  # years of a study in one place.
  test 'the submissions in a set are paginated' do
    3.times do
      request = @alice.submission_requests.create!(db: 'bioproject', status: :applied, migration_run_id: SecureRandom.uuid)
      @set.inclusions.create!(submission_request: request, added_by: @alice)
    end

    get set_path(@set)

    assert_conform_schema 200
    assert_equal 3, response.parsed_body['submissions'].size
    assert_equal '1', response.headers['Total-Pages']

    # The count is of everything in the set; the list is of one page of
    # it, so a page past the end is empty rather than a lie about size.
    get set_path(@set, page: 2)

    assert_conform_schema 200

    body = response.parsed_body

    assert_equal 3, body['submission_count']
    assert_empty body['submissions']
  end

  test 'the reason a set cannot be deleted is served, not left to the client to word' do
    @set.members.create!(email: 'newcomer@example.org', invited_by: @alice)

    get set_path(@set)

    assert_conform_schema 200

    body = response.parsed_body

    assert_equal false, body['deletable']
    assert_equal SubmissionSet::EMPTY_FIRST, body['delete_blocked_reason']
  end

  test 'an empty set of your own says it can go' do
    get set_path(@set)

    body = response.parsed_body

    assert_equal true, body['deletable']
    assert_nil body['delete_blocked_reason']
  end

  # Counted over the whole set. Counting the page on screen would tell
  # somebody "0 submissions" while the removal took sixty out.
  test 'each member carries what would go with them, past the end of the page' do
    2.times do
      request = @carol.submission_requests.create!(db: 'bioproject', status: :applied, migration_run_id: SecureRandom.uuid)
      @set.inclusions.create!(submission_request: request, added_by: @carol)
    end

    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    get set_path(@set, page: 2)

    assert_conform_schema 200

    body = response.parsed_body

    assert_empty body['submissions']
    assert_equal 2, body['members'].find { it['uid'] == @carol.uid }['submission_count']
  end

  # Serialising the remover was never enough on its own: the queued
  # writer still believed it was a member when it ran.
  test 'a write that queued behind a removal finds out it is no longer a member' do
    member = @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    member.remove!

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    with_exceptions_app do
      post set_members_path(@set), params: {set_member: {email: 'newcomer@example.org'}}.to_json, headers: JSON_HEADERS
    end

    assert_conform_schema 404
  end

  # A thread is DDBJ's record of what was asked and answered, and the
  # curator who answered has no copy anywhere else. Unlike the other two
  # blockers there is no step that clears it, so the set stays.
  test 'a set with a conversation on it cannot be deleted' do
    @set.messages.create!(user: @alice, author_role: :member, body: 'A question')

    get set_path(@set)

    assert_equal false, response.parsed_body.fetch('deletable')
    assert_match 'record of what was asked and answered', response.parsed_body.fetch('delete_blocked_reason')

    with_exceptions_app { delete set_path(@set) }

    assert_response :unprocessable_content
    assert SubmissionSet.exists?(@set.id)
  end
end
