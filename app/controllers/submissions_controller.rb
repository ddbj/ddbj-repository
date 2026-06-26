class SubmissionsController < ApplicationController
  def index
    scope = current_user.submissions
    scope = scope.where(db: params[:db]) if params[:db].present?

    pagy, @submissions = pagy(scope.order(id: :desc))

    response.headers.merge! pagy.headers_hash
  end

  def show
    @submission = current_user.submissions.find(params.expect(:id))
  end

  def create
    request = current_user.submission_requests.valid_only.joins(
      :validation
    ).where(
      validations: {
        finished_at: 1.day.ago..
      }
    ).find(params[:submission_request_id])

    raise ActiveRecord::RecordInvalid unless request.ready_to_apply?

    request.waiting_application!

    ApplySubmissionRequestJob.perform_later request

    head :no_content
  end
end
