# What is in a set, loaded the way a list page needs it: the curation
# state and accession summary for every submission on the page in one
# query each rather than per row — and only for the page.
#
# Paginated because there is no ceiling on what a set holds. A study
# that ran for three years is hundreds of submissions, each of which
# renders a progress block, and the set screen is not a place to
# discover that by timing out.
module SetContents
  extend ActiveSupport::Concern

  included do
    include AccessionSummaries
    include Pagy::Method
  end

  private

  # The set named by the path, and only if the caller is in it — a set
  # you are not in is not visible as a set you are not in, same reasoning
  # as the request scoping one floor up.
  #
  # Here rather than copied into each controller nested under `:set_id`:
  # it is the same three words in every one of them, and it is the line
  # that decides who may read the set at all.
  def load_set
    @set = SubmissionSet.joined_by(current_user).find(params.expect(:set_id))
  end

  # Take the set's own row, then ask again whether the caller is still
  # in it.
  #
  # Loading the set established that they were; a removal that starts
  # after that and commits before this write would otherwise leave the
  # thing they wrote behind — a submission nobody in the set can take
  # out, or an invitation that walks its sender back in. The remover
  # holds the same lock, so one of the two goes second and finds out.
  def within_submission_set_membership(set)
    set.with_lock do
      raise ActiveRecord::RecordNotFound, "Couldn't find SubmissionSet with 'id'=#{set.id}" unless set.member?(current_user)

      yield
    end
  end

  def load_set_contents
    scope = @set.inclusions
                  .includes(submission_request: [:user, {submission: :project}])
                  .order(:created_at, :id)

    pagy, @inclusions = pagy(scope)

    response.headers.merge! pagy.headers_hash

    requests = @inclusions.map(&:submission_request)

    @states                 = CurationState.batch(requests)
    @bs_accession_summaries = sample_accession_summaries(requests.filter_map(&:submission))

    # Only the viewer's own. An unread count says a conversation is going
    # on, and the conversations that predate a set are between one
    # submitter and DDBJ — being able to read somebody's submission here
    # is not being party to that.
    @unread_counts =
      SubmissionMessage
        .curator_role.unread
        .where(submission_request_id: requests.select { it.user_id == current_user.id }.map(&:id))
        .group(:submission_request_id)
        .count

    @counts = self.class.set_counts([@set.id], viewer: current_user)

    # How much goes with each member if they are removed. Counted here
    # rather than in the browser: the submissions on screen are one page
    # of however many there are, so counting what is visible would tell
    # somebody "0 submissions" while the removal took sixty out.
    @submission_counts =
      @set.inclusions
            .joins(:submission_request)
            .group('submission_requests.user_id')
            .count
  end

  class_methods do
    # Kept here as one call so the partial that reads them does not have
    # to know whether it is looking at one set or a page of them. The
    # counting itself belongs to the model.
    def set_counts(ids, viewer:)
      SubmissionSet.counts_for(ids).merge(unread: SubmissionSet.member_unread_counts(viewer, ids))
    end
  end
end
