class ReviewsController < ApplicationController
  # The whole point is unauthenticated access via the share token.
  skip_before_action :authenticate!, only: %i[show accessions]

  # An invalid OR expired token 404s (via find_by! on the `active` scope),
  # so a reviewer can't tell a revoked link from one that never existed.
  def show
    @request = reviewed_request
  end

  # The submission's entries, reachable via the share token. Its own view
  # rather than the submitter's: the two carried the same fields until one
  # of them gained a curation status, at which point sharing a template
  # meant an unauthenticated link had grown a window onto internal state.
  # They were never the same list — they only looked like it.
  def accessions
    submission = reviewed_request.submission or raise ActiveRecord::RecordNotFound

    pagy, @accessions = pagy(submission.entries.order(:id))
    response.headers.merge! pagy.headers_hash
  end

  private

  def reviewed_request
    ReviewerAccess.active.find_by!(token: params.expect(:token)).submission_request
  end
end
