class SubmissionsController < ApplicationController
  include Pagy::Backend

  def index
    submissions = search_submissions.order(id: :desc)

    pagy, @submissions = pagy(submissions, page: params[:page])

    pagy_headers_merge pagy
  rescue Pagy::OverflowError => e
    render json: {
      error: e.message
    }, status: :bad_request
  end

  def show
    @submission = user_submissions.find(params[:id].delete_prefix("X-"))
  end

  def create
    current_user.validations.find submission_params[:validation_id]

    validation  = Validation.find(params[:submission][:validation_id])
    param       = Database::MAPPING.fetch(validation.db)::Param.build(params)
    @submission = Submission.create!(**submission_params, param:)

    SubmitJob.perform_later @submission

    render status: :created
  end

  private

  def submission_params
    params.require(:submission).permit(:validation_id, :visibility)
  end

  def user_submissions
    current_user.submissions.includes(
      validation: [
        :user,

        objs: [
          :file_blob,
          :validation_details
        ]
      ]
    )
  end

  def search_submissions
    db, created_at_after, created_at_before = params.values_at(:db, :created_at_after, :created_at_before)

    submissions = user_submissions

    submissions = submissions.where(validations: { db: db.split(",") })              if db
    submissions = submissions.where(created_at: created_at_after..created_at_before) if created_at_after || created_at_before

    submissions
  end
end
