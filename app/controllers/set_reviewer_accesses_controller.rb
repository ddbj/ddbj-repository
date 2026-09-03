# The set's review link. One per set, and any member may enable it, mint
# a fresh URL or revoke it — see ReviewerAccess for why revoking in
# particular is nobody's to wait for.
#
# What the link carries is not decided here: SetSharedAccessionsController
# holds that, because each accession on it is the business of whoever owns
# the submission it belongs to.
class SetReviewerAccessesController < ApplicationController
  include SetContents

  before_action :refuse_proxy!, only: %i[create destroy]
  before_action :load_set

  def show
    load_link
  end

  # Enabling and re-minting are one press. The old URL stops working,
  # which is what somebody replacing a link they have lost control of
  # expects — and what is on the link survives it, because the accessions
  # belong to the members who put them there and replacing a URL is not
  # un-sharing their work.
  def create
    within_submission_set_membership(@set) do
      ReviewerAccess.enable!(@set, created_by: current_user, expires_at: reviewer_access_params[:expires_at])
    end

    load_link
    render :show, status: :created
  end

  # Revoking takes the accessions with it. They were named on this link,
  # and a link that no longer exists is not a place to keep a list —
  # whereas a fresh URL that arrived already carrying somebody's work
  # would be sharing it without anybody having said so.
  #
  # Under the lock like every other write to a set, and for the concrete
  # reason: a colleague putting an accession on the link holds it across
  # the read and the insert, and revoking between the two would leave
  # their insert pointing at a link that no longer exists.
  def destroy
    within_submission_set_membership(@set) do
      @set.reviewer_access&.destroy!
    end

    head :no_content
  end

  private

  # The link itself, and how much is on it — not what is on it. That list
  # has no ceiling (see ReviewerAccess) and is read a page at a time from
  # the nested route; a screen that has just been told a URL and an expiry
  # does not need a hundred thousand rows to draw its first frame.
  def load_link
    @access = @set.reviewer_access

    @count = @access ? @access.shared_accessions.count : 0

    # How much of it is not the reader's, so that Revoke can say what it
    # costs before it fires — anybody in the set may revoke, and taking
    # somebody else's work off the link is the part they cannot undo for
    # them. Counted from `added_by` rather than by resolving every row to
    # its owner: only an owner can put an accession here, so the two are
    # the same answer and one of them is a single indexed count.
    @others = @access ? @access.shared_accessions.where.not(added_by_id: current_user.id).count : 0
  end

  def reviewer_access_params = params.expect(reviewer_access: %i[expires_at])
end
