class AccessionsController < ApplicationController
  def index
    submission = current_user.submissions.find(params[:submission_id])

    pagy, @accessions = pagy(submission.entries.order(:id))

    response.headers.merge! pagy.headers_hash
  end

  def show
    @accession = Entry.joins(:submission).merge(current_user.submissions).find_by!(accession: params[:number])
  end
end
