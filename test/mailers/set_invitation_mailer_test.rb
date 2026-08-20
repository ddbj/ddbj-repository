require 'test_helper'

class SetInvitationMailerTest < ActionMailer::TestCase
  setup do
    @alice  = users(:alice)
    @set  = SubmissionSet.create!(name: 'Deep sea study', owner: @alice)
    @member = @set.members.create!(email: 'newcomer@example.org', invited_by: @alice)
  end

  test 'goes to the address that was typed, not to an account' do
    mail = SetInvitationMailer.with(member: @member).invite

    assert_equal ['newcomer@example.org'], mail.to
    assert_match 'Deep sea study', mail.subject
  end

  test 'carries the link that is live now' do
    mail = SetInvitationMailer.with(member: @member).invite

    assert_match @member.invitation_url, mail.text_part.body.to_s
    assert_match @member.invitation_url, mail.html_part.body.to_s
  end

  test 'a resend carries the new link and not the old one' do
    was = @member.invitation_url

    @member.resend!

    body = SetInvitationMailer.with(member: @member).invite.text_part.body.to_s

    assert_match @member.invitation_url, body
    assert_no_match(/#{Regexp.escape(was)}/, body)
  end
end
