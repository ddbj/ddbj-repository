class SubmissionUpdatesController < ApplicationController
  def show
    @update = current_user.submission_updates.where(db: params[:db]).find(params[:id])
  end

  def create
    submission = current_user.submissions.where(db: params[:db]).find(params[:submission_id])
    @update    = submission.updates.create!(**update_params, db: params[:db])

    raise ActiveRecord::RecordInvalid unless @update.waiting_validation?

    ValidateDDBJRecordJob.perform_later @update
    CalculateDDBJRecordDiffJob.perform_later @update

    render :show, status: :accepted
  end

  private

  def update_params
    params.expect(submission_update: [
      :ddbj_record
    ])
  end
end
