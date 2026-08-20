class ReviewsController < ApplicationController
  include AttachmentDownload

  # The whole point is unauthenticated access via the share token.
  skip_before_action :authenticate!, only: %i[show accessions file]

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

  # Files, on the same token as everything else here. Which is the point:
  # revoking the share revokes these too, where a bare Active Storage URL
  # the reviewer had collected would have gone on working for ever.
  #
  # `submission_record` rather than `ddbj_record` for the applied one, so
  # the two uploads a reviewer can see are not one word apart.
  NAMES = {
    'ddbj_record'       => ->(request) { request.ddbj_record },
    'submission_record' => ->(request) { request.submission&.ddbj_record },
    'flatfile_na'       => ->(request) { request.submission&.flatfile_na },
    'flatfile_aa'       => ->(request) { request.submission&.flatfile_aa }
  }.freeze

  def file
    redirect_to_attachment NAMES.fetch(params[:name]).call(reviewed_request)
  end

  private

  def reviewed_request
    ReviewerAccess.active.find_by!(token: params.expect(:token)).submission_request
  end
end
