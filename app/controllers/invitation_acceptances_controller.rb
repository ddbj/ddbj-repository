# Walking through the link. Authenticated, because this is the moment an
# account is attached to the seat.
#
# The token is what is checked, not the address it was mailed to. See
# SubmissionSetMember for why, and for what the roster shows in exchange.
class InvitationAcceptancesController < ApplicationController
  include SetContents

  # Joining a set is a membership write like any other, and the row
  # records the account that made it — under a proxy that would be the
  # person being helped rather than the curator helping.
  before_action :refuse_proxy!

  def create
    member = SubmissionSetMember.find_by!(invitation_token: params.expect(:invitation_token).presence)
    @set = member.set

    # Under a lock, and re-read inside it. Two people holding the same
    # forwarded link would otherwise both pass the checks and both write
    # the row: the loser is told they joined and has not, with the link
    # already spent.
    @set.with_lock do
      member.reload

      # Already in, by some other route — a second invitation, or this one
      # from another tab. Not an error: they wanted to be in the set and
      # they are. The invitation is spent rather than left outstanding for
      # ever, which is what used to make it block the set's deletion.
      if @set.member?(current_user)
        member.destroy! if member.pending?
        next
      end

      refuse! 'This invitation has already been used.' if member.joined?
      refuse! 'This invitation has expired. Ask a member of the set to send it again.' if member.invitation_expired?

      member.accept!(current_user)
    end

    @counts = self.class.set_counts([@set.id], viewer: current_user)

    render status: :created
  end
end
