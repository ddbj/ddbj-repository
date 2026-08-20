require 'test_helper'

class SubmissionSetMemberTest < ActiveSupport::TestCase
  setup do
    @alice = users(:alice)
    @carol = users(:carol)
    @set = SubmissionSet.create!(name: 'Deep sea study', owner: @alice)
  end

  test 'the creator is on the roster, with no invitation to walk through' do
    member = @set.members.sole

    assert_equal @alice, member.user
    assert member.joined?
    assert_nil member.email
    assert_nil member.invitation_token
  end

  test 'an invitation carries a token and a clock' do
    member = @set.members.create!(email: 'newcomer@example.org', invited_by: @alice)

    assert member.pending?
    assert_equal 32, member.invitation_token.length
    assert_in_delta SubmissionSetMember::INVITATION_VALIDITY.from_now, member.invitation_expires_at, 5
    assert_not member.invitation_expired?
  end

  test 'the address is stored the way a person would read it back' do
    member = @set.members.create!(email: '  Newcomer@Example.ORG ', invited_by: @alice)

    assert_equal 'newcomer@example.org', member.email
  end

  test 'accepting keeps the token, so the link can explain itself when it is opened again' do
    member = @set.members.create!(email: 'newcomer@example.org', invited_by: @alice)
    token  = member.invitation_token

    member.accept!(@carol)

    assert member.joined?
    assert_equal token, member.invitation_token
    assert_equal 'accepted', member.invitation_state
    assert @set.member?(@carol)
  end

  test 'an invitation says which of its three states it is in' do
    member = @set.members.create!(email: 'newcomer@example.org', invited_by: @alice)

    assert_equal 'open', member.invitation_state

    member.update_columns(invitation_expires_at: 1.day.ago)
    assert_equal 'expired', member.reload.invitation_state

    member.update_columns(invitation_expires_at: 1.day.from_now)
    member.reload.accept!(@carol)
    assert_equal 'accepted', member.invitation_state
  end

  test 'resending is refused on somebody who has already joined, rather than left to the check constraint' do
    member = @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    assert_raises(ArgumentError) { member.resend! }
  end

  test 'removing somebody takes back the invitations they sent' do
    member = @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    # Any member may invite, so a member who is asked to leave could
    # otherwise walk straight back in through a link they sent themselves.
    theirs = @set.members.create!(email: 'mallory-2@example.org', invited_by: @carol)
    mine   = @set.members.create!(email: 'newcomer@example.org',  invited_by: @alice)

    member.remove!

    assert_not SubmissionSetMember.exists?(theirs.id)
    assert     SubmissionSetMember.exists?(mine.id)
  end

  test 'the roster says whether the account matches the address the invitation went to' do
    @carol.update!(email: 'carol@example.com')

    forwarded = @set.members.create!(email: 'forwarded-to@example.org', invited_by: @alice)
    forwarded.accept!(@carol)

    assert_equal 'different', forwarded.invited_address_match
  end

  test 'accepting at the address it was sent to is unremarkable' do
    @carol.update!(email: 'carol@example.com')

    member = @set.members.create!(email: 'Carol@Example.com', invited_by: @alice)
    member.accept!(@carol)

    assert_equal 'same', member.invited_address_match
  end

  # Most accounts imported from D-way have never signed in and carry no
  # address. Saying "same" for one of those would put a claim on the
  # roster that nothing checked.
  test 'an account with no address on file is unknown rather than matching' do
    @carol.update!(email: nil)

    member = @set.members.create!(email: 'newcomer@example.org', invited_by: @alice)
    member.accept!(@carol)

    assert_equal 'unknown', member.invited_address_match
  end

  test 'the creator was never invited, so the question does not arise' do
    assert_nil @set.members.sole.invited_address_match
  end

  test 'resending replaces the link rather than adding one' do
    member = @set.members.create!(email: 'newcomer@example.org', invited_by: @alice)
    was    = member.invitation_token

    travel 1.day do
      member.resend!
    end

    assert_not_equal was, member.invitation_token
    assert_operator member.invitation_expires_at, :>, SubmissionSetMember::INVITATION_VALIDITY.from_now
  end

  test 'removing somebody takes their submissions out with them, and leaves everyone else alone' do
    member = @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    theirs = @carol.submission_requests.create!(db: 'bioproject', status: :applied, migration_run_id: SecureRandom.uuid)
    mine   = submission_requests(:bioproject)

    @set.inclusions.create!(submission_request: theirs, added_by: @carol)
    @set.inclusions.create!(submission_request: mine,   added_by: @alice)

    member.remove!

    assert_equal [mine], @set.inclusions.reload.map(&:submission_request)
  end

  test 'one account cannot hold two seats in the same set' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    second = @set.members.build(user: @carol, invited_by: @alice, joined_at: Time.current)

    assert_not second.valid?
  end

  test 'a set is deletable only once it is nobody else and nothing else' do
    assert @set.deletable?

    member = @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)
    assert_not @set.deletable?

    member.remove!
    assert @set.reload.deletable?

    # An invitation sitting unused in somebody's mailbox counts as
    # somebody: deleting the set would kill that link silently.
    invitation = @set.members.create!(email: 'newcomer@example.org', invited_by: @alice)
    assert_not @set.reload.deletable?

    invitation.remove!
    assert @set.reload.deletable?

    @set.inclusions.create!(submission_request: submission_requests(:bioproject), added_by: @alice)
    assert_not @set.reload.deletable?
  end

  test 'a submission can only be put in a set by its owner' do
    @set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)

    intruder = @set.inclusions.build(submission_request: submission_requests(:bioproject), added_by: @carol)

    assert_not intruder.valid?
  end

  test 'the same submission can be in more than one set' do
    other   = SubmissionSet.create!(name: 'Another study', owner: @alice)
    request = submission_requests(:bioproject)

    @set.inclusions.create!(submission_request: request, added_by: @alice)
    other.inclusions.create!(submission_request: request, added_by: @alice)

    assert_equal 2, request.sets.count
  end
end
