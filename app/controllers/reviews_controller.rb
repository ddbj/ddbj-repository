class ReviewsController < ApplicationController
  # The whole point is unauthenticated access via the share token.
  skip_before_action :authenticate!, only: %i[show]

  # An invalid OR expired token 404s (via find_by! on the `active` scope),
  # so a reviewer can't tell a revoked link from one that never existed.
  #
  # One action, and it answers with what was shared rather than with the
  # submissions the accessions came from. That is the change of
  # granularity: at accession granularity there is no file to hand over —
  # a record or a flatfile is the whole submission, and the whole
  # submission is the thing that was deliberately not shared — so what a
  # reviewer gets is what these accessions say, drawn on the page.
  def show
    @access = ReviewerAccess.active.find_by!(token: params.expect(:token))
    @rows   = @access.shared_rows
  end
end
