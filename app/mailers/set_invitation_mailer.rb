# "You have been invited to a set." Sent on the invitation and again on
# every resend — each time with the link that is live now, since a resend
# replaces the old one.
class SetInvitationMailer < ApplicationMailer
  def invite
    @member  = params[:member]
    @set   = @member.set
    @inviter = @member.invited_by

    # Straight to the address that was typed, not through `recipient_for`:
    # the whole point is that this may reach somebody the system has never
    # heard of, so there is no account to look an address up on.
    mail(to: @member.email, subject: "[DDBJ Repository] You have been invited to “#{@set.name}”")
  end
end
