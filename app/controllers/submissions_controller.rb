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

    # Closed means "not taking this further", and applying it anyway
    # would leave `closed_at` set through curation and release — where
    # the client reads it before everything else and would report a
    # public record as one the submitter had put down. Reopening first is
    # what the screen already tells them to do.
    raise ActiveRecord::RecordInvalid if request.closed?
    raise ActiveRecord::RecordInvalid unless request.ready_to_apply?

    request.waiting_application!

    ApplySubmissionRequestJob.perform_later request

    head :no_content
  end
end
