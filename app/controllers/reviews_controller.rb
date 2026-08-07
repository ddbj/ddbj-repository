class ReviewsController < ApplicationController
  # The whole point is unauthenticated access via the share token.
  skip_before_action :authenticate!, only: %i[show accessions]

  # An invalid OR expired token 404s (via find_by! on the `active` scope),
  # so a reviewer can't tell a revoked link from one that never existed.
  def show
    @request = reviewed_request
  end

  # Same accessions a submitter sees, reachable via the share token. Reuses
  # the submitter accessions view.
  def accessions
    submission = reviewed_request.submission or raise ActiveRecord::RecordNotFound

    pagy, @accessions = pagy(submission.entries.order(:id))
    response.headers.merge! pagy.headers_hash

    render 'accessions/index'
  end

  private

  def reviewed_request
    ReviewerAccess.active.find_by!(token: params.expect(:token)).submission_request
  end
end
