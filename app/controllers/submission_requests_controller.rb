class SubmissionRequestsController < ApplicationController
  def index
    scope = current_user.submission_requests.includes(submission: :accessions)
    scope = scope.where(db: params[:db]) if params[:db].present?

    pagy, @requests = pagy(scope.order(id: :desc))

    response.headers.merge! pagy.headers_hash
  end

  def show
    @request = current_user.submission_requests.find(params.expect(:id))
  end

  def create
    @request = current_user.submission_requests.create!(**request_params)

    raise ActiveRecord::RecordInvalid unless @request.waiting_validation?

    ValidateDDBJRecordJob.perform_later @request

    render :show, status: :accepted
  end

  private

  def request_params
    params.expect(submission_request: %i[db ddbj_record])
  end
end
