require 'test_helper'

class SubmissionSetMembersTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = {'Content-Type' => 'application/json'}.freeze

  setup do
    @alice = users(:alice)
    @carol = users(:carol)

    default_headers['Authorization'] = "Bearer #{@alice.api_key}"

    @set = SubmissionSet.create!(name: 'Deep sea study', owner: @alice)
  end

  test 'inviting mails the address a single-use link' do
    assert_difference 'SubmissionSetMember.count', 1 do
      assert_enqueued_emails 1 do
        post set_members_path(@set),
             params:  {set_member: {email: ' Newcomer@Example.ORG '}}.to_json,
             headers: JSON_HEADERS
      end
    end

    assert_conform_schema 201

    body = response.parsed_body

    assert_equal 'newcomer@example.org', body['email']
    assert_equal 'open', body['status']
    assert_nil   body['uid']
  end

  test 'any member can invite, not just the owner' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    post set_members_path(@set), params: {set_member: {email: 'newcomer@example.org'}}.to_json, headers: JSON_HEADERS

    assert_conform_schema 201
  end

  test 'inviting somebody already on the roster is refused' do
    @carol.update!(email: 'carol@example.com')
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    with_exceptions_app do
      post set_members_path(@set),
           params:  {set_member: {email: 'Carol@Example.com'}}.to_json,
           headers: JSON_HEADERS
    end

    assert_conform_schema 422
  end

  test 'resending mints a new token and kills the old link' do
    member = @set.members.create!(email: 'newcomer@example.org', invited_by: @alice)
    was    = member.invitation_token

    assert_enqueued_emails 1 do
      post set_member_reminder_path(@set, member)
    end

    assert_conform_schema 201
    assert_not_equal was, member.reload.invitation_token
  end

  test 'resending to somebody who has already joined is refused' do
    member = @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    with_exceptions_app do
      post set_member_reminder_path(@set, member)
    end

    assert_conform_schema 422
  end

  test 'a member can leave, and their submissions go with them' do
    member = @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    carols = @carol.submission_requests.create!(db: 'bioproject', status: :applied, migration_run_id: SecureRandom.uuid)
    @set.inclusions.create!(submission_request: carols, added_by: @carol)

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    delete set_member_path(@set, member)

    assert_conform_schema 204
    assert_empty @set.inclusions.reload
  end

  test 'one member cannot remove another' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    dave   = users(:dave)
    target = @set.members.create!(user: dave, invited_by: @alice, joined_at: Time.current)

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    with_exceptions_app do
      delete set_member_path(@set, target)
    end

    assert_conform_schema 403
  end

  test 'the owner can remove anybody' do
    target = @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    delete set_member_path(@set, target)

    assert_conform_schema 204
  end

  test 'the person who sent an invitation can take it back' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    post set_members_path(@set), params: {set_member: {email: 'newcomer@example.org'}}.to_json, headers: JSON_HEADERS

    delete set_member_path(@set, response.parsed_body['id'])

    assert_conform_schema 204
  end

  test 'the owner cannot walk out of their own set' do
    with_exceptions_app do
      delete set_member_path(@set, @set.members.find_by!(user_id: @alice.id))
    end

    assert_conform_schema 422
  end

  # Every deployed environment restricts outgoing mail while sending to
  # real submitters is switched off. Without this the feature looks like
  # it works and reaches nobody — so the answer says whether the mail left
  # the building, and hands over the link either way.
  test 'the answer says whether the mail actually goes anywhere, and carries the link regardless' do
    restrict_mail_to('ddbj.nig.ac.jp') do
      post set_members_path(@set),
           params:  {set_member: {email: 'colleague@university.edu'}}.to_json,
           headers: JSON_HEADERS

      assert_conform_schema 201

      body = response.parsed_body

      assert_equal false, body['mail_deliverable']
      assert_match %r{/web/invitations/.+}, body['invitation_url']
    end
  end

  test 'a link is only offered while the invitation is outstanding' do
    member = @set.members.create!(email: 'newcomer@example.org', invited_by: @alice)
    member.accept!(@carol)

    get set_path(@set)

    assert_conform_schema 200

    row = response.parsed_body['members'].find { it['uid'] == @carol.uid }

    assert_nil row['invitation_url']
    assert_nil row['mail_deliverable']
  end

  test 'the roster says what each row may have done to it' do
    invited = @set.members.create!(email: 'newcomer@example.org', invited_by: @alice)
    joined  = @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    get set_path(@set)

    rows = response.parsed_body['members'].index_by { it['id'] }

    assert_equal false, rows.fetch(@set.members.find_by!(user_id: @alice.id).id)['removable'] # the owner's own row
    assert_equal true,  rows.fetch(invited.id)['removable']
    assert_equal true,  rows.fetch(joined.id)['removable']

    # ...and the same roster read by somebody who is not the owner.
    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    get set_path(@set)

    rows = response.parsed_body['members'].index_by { it['id'] }

    assert_equal true,  rows.fetch(joined.id)['removable']  # leaving
    assert_equal false, rows.fetch(invited.id)['removable'] # somebody else's invitation
  end

  test 'a member who invited somebody can take that invitation back' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    post set_members_path(@set), params: {set_member: {email: 'newcomer@example.org'}}.to_json, headers: JSON_HEADERS

    assert_equal true, response.parsed_body['removable']

    delete set_member_path(@set, response.parsed_body['id'])

    assert_conform_schema 204
  end

  test 'a set you are not in has no roster to write to' do
    other = SubmissionSet.create!(name: 'Not yours', owner: @carol)

    with_exceptions_app do
      post set_members_path(other), params: {set_member: {email: 'newcomer@example.org'}}.to_json, headers: JSON_HEADERS
    end

    assert_conform_schema 404

    member = other.members.sole

    with_exceptions_app { delete set_member_path(other, member) }
    assert_conform_schema 404

    with_exceptions_app { post set_member_reminder_path(other, member) }
    assert_conform_schema 404
  end

  # Acting as somebody else is for helping them with what they submitted.
  # Deciding who they collaborate with is not that, and the row would
  # record the wrong person as having done it.
  test 'a curator acting as somebody else cannot write to their sets' do
    curator = users(:bob)

    default_headers['Authorization']   = "Bearer #{curator.api_key}"
    default_headers['X-Dway-User-Id']  = @alice.uid

    with_exceptions_app do
      post set_members_path(@set), params: {set_member: {email: 'newcomer@example.org'}}.to_json, headers: JSON_HEADERS
    end

    assert_conform_schema 403

    # Reading is untouched.
    get set_path(@set)

    assert_conform_schema 200
  end
end
