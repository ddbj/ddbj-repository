class SubmissionRequestsController < ApplicationController
  def index
    requests = current_user.submission_requests.includes(
      :submission,
      validation_with_validity: :details,
    )

    pagy, @requests = pagy(requests.order(id: :desc))

    response.headers.merge! pagy.headers_hash
  end

  def show
    @request = current_user.submission_requests.find(params[:id])
  end

  def create
    @request = current_user.submission_requests.create!(request_params)

    ValidateSubmissionRequestJob.perform_later @request

    render :show, status: :accepted
  end

  private

  def request_params
    params.expect(submission_request: [
      :ddbj_record
    ])
  end
end
