class ReviewsController < ApplicationController
  # The whole point is unauthenticated access via the share token.
  skip_before_action :authenticate!, only: %i[show]

  # An invalid OR expired token 404s (via find_by! on the `active` scope),
  # so a reviewer can't tell a revoked link from one that never existed.
  def show
    reviewer_access = ReviewerAccess.active.find_by!(token: params.expect(:token))
    @request = reviewer_access.submission_request
  end
end
