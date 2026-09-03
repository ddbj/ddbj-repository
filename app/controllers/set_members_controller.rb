# The roster. Inviting somebody and taking them off are the same list
# being written to, so they are the same resource — see SubmissionSetMember for
# why an outstanding invitation is a row on it rather than a queue beside
# it.
class SetMembersController < ApplicationController
  include SetContents

  before_action :refuse_proxy!
  before_action :load_set
  before_action :load_member, only: %i[destroy]

  # An invitation is mail sent from `repo@ddbj.nig.ac.jp` to an address
  # somebody typed, so the ceiling is on people rather than on sets: a
  # real collaboration invites a handful in a sitting, and nothing that
  # is not an attempt to use us as a mail relay invites eighty.
  rate_limit to: 30, within: 1.hour, by: -> { current_user&.id }, only: %i[create],
             with: -> { render json: {error: 'Too many invitations in a short time. Try again later.'}, status: :too_many_requests }

  # Any member invites. A collaboration is not organised around whoever
  # happened to press New first, and an invitation that has to wait for
  # them is one that does not go out.
  def create
    within_submission_set_membership(@set) do
      @member = @set.members.create!(email: member_params[:email], invited_by: current_user)
    end

    SetInvitationMailer.with(member: @member).invite.deliver_later

    render :show, status: :created
  end

  # Leaving, revoking an invitation that has not been used, and removing
  # somebody are one act with three names.
  def destroy
    authorize_removal!

    @member.remove!

    head :no_content
  end

  private

  def authorize_removal!
    return if @member.user_id == current_user.id                            # leaving
    return if @set.owned_by?(current_user)                                # the owner's set to keep in order
    return if @member.pending? && @member.invited_by_id == current_user.id  # taking back your own invitation

    forbid! 'Only the owner can remove another member.'
  end

  # The owner cannot walk out of their own set: nothing would then say
  # who may rename or delete it, and the set would be left with no way
  # to be put down. Deleting it is the way out, which is why it is
  # refused rather than hidden.
  def load_member
    @member = @set.members.find(params.expect(:id))

    return unless @member.user_id == @set.owner_id

    refuse! 'The owner cannot leave their own set. Delete it instead.' if @member.user_id == current_user.id
  end

  def member_params = params.expect(set_member: %i[email])
end
