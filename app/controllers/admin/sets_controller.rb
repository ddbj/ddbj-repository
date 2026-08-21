module Admin
  # The set axis: conversations about a bundle of submissions rather than
  # about one of them.
  #
  # A second axis is a real cost — unread and following are now asked in
  # two places — and it is paid for by the alternative: a question about
  # twelve submissions written into twelve request threads arrives in a
  # curator's queue twelve times, so answering it means answering it
  # twelve times. The duplication the submitter avoided by asking once
  # would simply have been handed to whoever answers.
  #
  # There is no assignment here. A set has no state to move through and
  # nothing to hand over but the conversation, so "who is dealing with
  # this" is answered by who is following it — which is a thing curators
  # already read on the request axis.
  class SetsController < ApplicationController
    include Pagy::Method

    # Two filters and no search. A set is found by the conversation it is
    # having — which is the only reason a curator is on this screen —
    # and there are not enough of them for a name to be the way in.
    def index
      @waiting = SubmissionSet.needing_curator(current_user).count
      @total   = SubmissionSet.count

      scope = SubmissionSet.includes(:owner).order(updated_at: :desc)
      scope = scope.merge(SubmissionSet.needing_curator(current_user)) if params[:filter] == 'waiting'
      scope = scope.merge(SubmissionSet.followed_by(current_user))     if params[:filter] == 'following'

      @pagy, @sets = pagy(scope)

      ids = @sets.map(&:id)

      @counts     = SubmissionSet.counts_for(ids)
      @unread     = SubmissionSet.curator_unread_counts(current_user, ids)
      @last_posts = SubmissionSetMessage.where(submission_set_id: ids).group(:submission_set_id).maximum(:created_at)
    end

    def show
      @set = SubmissionSet.includes(:owner).find(params.expect(:id))

      # The thread renders each message's attachments as well as its
      # author — `:user` alone leaves a pair of queries per message.
      @messages   = @set.messages.includes(:user, files_attachments: :blob).to_a
      @members    = @set.members.ordered.includes(:user, :invited_by).to_a
      @inclusions = @set.inclusions.includes(submission_request: [:user, {submission: :project}]).order(:created_at)
    end
  end
end
