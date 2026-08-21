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

    helper_method :waiting?, :following?

    # Two filters and no search. A set is found by the conversation it is
    # having — which is the only reason a curator is on this screen —
    # and there are not enough of them for a name to be the way in.
    #
    # The two are independent, not a three-way switch: "which of the ones
    # I follow still need me?" is the obvious question to ask of this
    # screen, and a single slot would answer it with the wrong list
    # rather than say it cannot.
    def index
      @waiting = SubmissionSet.needing_curator(current_user).count
      @total   = SubmissionSet.count

      # `where(id:)` twice rather than two `merge`s: merging relations
      # that both constrain `id` REPLACES the first condition rather than
      # narrowing it, so asking both questions used to silently answer
      # only the second.
      scope = SubmissionSet.includes(:owner, :assignee).order(updated_at: :desc)
      scope = scope.where(id: SubmissionSet.needing_curator(current_user).select(:id)) if waiting?
      scope = scope.where(id: SubmissionSet.followed_by(current_user).select(:id))     if following?

      @pagy, @sets = pagy(scope)

      # A page past the end renders an empty table under a filter bar
      # counting the rows that are there — the screen contradicting
      # itself. Reachable by hand and by carrying a page number back.
      return if redirect_out_of_range_page(@pagy)

      ids = @sets.map(&:id)

      @counts     = SubmissionSet.counts_for(ids)
      @unread     = SubmissionSet.curator_unread_counts(current_user, ids)
      @last_posts = SubmissionSetMessage.where(submission_set_id: ids).group(:submission_set_id).maximum(:created_at)

      # Who is already curating what is in each set — see
      # ViewHelpers#assignee_breakdown for why this belongs next to the
      # conversation rather than on the submissions.
      @assignees     = SubmissionSet.assignee_counts(ids)
      @assignee_uids = assignee_uids(@assignees)
    end


    def show
      @set = SubmissionSet.includes(:owner, :assignee).find(params.expect(:id))

      # The thread renders each message's attachments as well as its
      # author — `:user` alone leaves a pair of queries per message.
      @messages = @set.messages.includes(:user, files_attachments: :blob).to_a
      @members  = @set.members.ordered.includes(:user, :invited_by).to_a

      # Paginated: a set holds however much it holds, and a three-year
      # study is hundreds of submissions. The member's own view of the
      # same list paginates for the same reason.
      @pagy, @inclusions = pagy(
        @set.inclusions
              .includes(submission_request: [:user, :assignee, {submission: :project}])
              .order(:created_at, :id)
      )

      redirect_out_of_range_page(@pagy)
    end

    private

    # One lookup for every name any of the rows will print.
    def assignee_uids(counts)
      ids = counts.values.flat_map(&:keys).compact.uniq

      User.where(id: ids).pluck(:id, :uid).to_h
    end

    # Unrecognised values mean nothing rather than something: a `filter`
    # the screen does not know used to render the whole list with no
    # button lit, silently ignoring what it was asked for.
    def waiting?   = params[:waiting].present?
    def following? = params[:following].present?
  end
end
