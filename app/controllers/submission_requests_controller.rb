class SubmissionRequestsController < ApplicationController
  def index
    pagy, @requests = pagy(current_user.submission_requests.order(id: :desc))

    response.headers.merge! pagy.headers_hash
  end

  def show
    @request = current_user.submission_requests.find(params[:id])
  end

  def create
    @request = current_user.submission_requests.create!(request_params)

    raise ActiveRecord::RecordInvalid unless @request.waiting_validation?

    ValidateDDBJRecordJob.perform_later @request

    render :show, status: :accepted
  end

  private

  def request_params
    params.expect(submission_request: [
      :ddbj_record
    ])
  end
end
