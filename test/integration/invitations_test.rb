require 'test_helper'

class InvitationsTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)
    @carol = users(:carol)

    @set  = SubmissionSet.create!(name: 'Deep sea study', owner: @alice)
    @member = @set.members.create!(email: 'newcomer@example.org', invited_by: @alice)
  end

  test 'the landing page reads without an account' do
    get invitation_path(@member.invitation_token)

    assert_conform_schema 200

    body = response.parsed_body

    assert_equal 'Deep sea study',       body['set_name']
    assert_equal @alice.uid,             body['invited_by']
    assert_equal 'newcomer@example.org', body['email']
    assert_equal 'open',                 body['status']
  end

  test 'an expired invitation says so rather than hiding' do
    @member.update_columns(invitation_expires_at: 1.day.ago)

    get invitation_path(@member.invitation_token)

    assert_conform_schema 200
    assert_equal 'expired', response.parsed_body['status']
  end

  # The token is kept after acceptance for exactly this: somebody opening
  # the mail again from another device is told what happened rather than
  # shown a 404 for a link that worked perfectly.
  test 'a link that has already been used says so' do
    @member.accept!(@carol)

    get invitation_path(@member.invitation_token)

    assert_conform_schema 200
    assert_equal 'accepted', response.parsed_body['status']
  end

  test 'an unknown token is not found' do
    with_exceptions_app do
      get invitation_path('nope')
    end

    assert_conform_schema 404
  end

  test 'accepting joins the set, whatever address the account is registered at' do
    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    post invitation_acceptance_path(@member.invitation_token)

    assert_conform_schema 201
    assert_equal 'Deep sea study', response.parsed_body['name']

    @member.reload

    assert_equal @carol.id, @member.user_id
    assert       @set.member?(@carol)
  end

  test 'the link stops working once somebody has walked through it' do
    token = @member.invitation_token

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"
    post invitation_acceptance_path(token)

    default_headers['Authorization'] = "Bearer #{users(:dave).api_key}"

    with_exceptions_app do
      post invitation_acceptance_path(token)
    end

    assert_conform_schema 422
    assert_not @set.member?(users(:dave))
  end

  test 'an expired invitation cannot be walked through' do
    @member.update_columns(invitation_expires_at: 1.day.ago)

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    with_exceptions_app do
      post invitation_acceptance_path(@member.invitation_token)
    end

    assert_conform_schema 422
  end

  # Two people inviting the same person is a thing that happens. They
  # wanted to be in the set and they are, so the second link is simply
  # spent — left outstanding it would count against the set for ever
  # and block its deletion.
  test 'a second invitation to a set you are already in is spent, not refused' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    default_headers['Authorization'] = "Bearer #{@carol.api_key}"

    post invitation_acceptance_path(@member.invitation_token)

    assert_conform_schema 201
    assert_not SubmissionSetMember.exists?(@member.id)
  end

  test 'accepting without logging in is refused' do
    post invitation_acceptance_path(@member.invitation_token)

    assert_conform_schema 401
  end
end
