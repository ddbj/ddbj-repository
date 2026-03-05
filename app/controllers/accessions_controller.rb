class AccessionsController < ApplicationController
  def index
    submission = current_user.submissions.find(params[:submission_id])

    pagy, @accessions = pagy(submission.accessions.order(:id))

    response.headers.merge! pagy.headers_hash
  end
end
