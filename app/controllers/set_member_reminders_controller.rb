# Sending an invitation again. A new token and a new clock, so the link
# that did not get used stops working — somebody asking for a resend is
# replacing a link, not handing out a second one.
#
# Any member can do it: the point of a resend is usually that whoever
# sent the first one is not around.
class SetMemberRemindersController < ApplicationController
  include SetContents

  before_action :refuse_proxy!
  before_action :load_set
  before_action :load_member

  def create
    refuse! 'That person has already joined.' if @member.joined?

    @member.resend!

    SetInvitationMailer.with(member: @member).invite.deliver_later

    render 'set_members/show', status: :created
  end

  private

  def load_member = @member = @set.members.find(params.expect(:member_id))
end
