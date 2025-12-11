class SubmissionsController < ApplicationController
  def show
    @submission = current_user.submissions.includes(
      :updates
    ).order(
      'submission_updates.id DESC'
    ).find(params.expect(:id))
  end

  def create
    request = current_user.submission_requests.valid_only.joins(
      :validation
    ).where(
      validations: {
        finished_at: 1.day.ago..
      }
    ).find(params[:submission_request_id])

    ApplySubmissionRequestJob.perform_later request

    head :accepted
  end

  def update
    update = current_user.submission_updates.valid_only.joins(
      :validation
    ).where(
      validations: {
        finished_at: 1.day.ago..
      }
    ).find(params[:submission_update_id])

    ApplySubmissionUpdateJob.perform_later update

    head :accepted
  end
end
