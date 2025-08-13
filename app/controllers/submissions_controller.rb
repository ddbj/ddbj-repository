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
    @submission = user_submissions.find(params.expect(:id))
  end

  def create
    validation  = current_user.validations.find(params.require(:validation_id))
    param       = Database::MAPPING.fetch(validation.db).build_param(params)
    @submission = Submission.create!(**submission_params, param:)

    SubmitJob.perform_later @submission

    render status: :created
  end

  private

  def submission_params
    params.permit(:validation_id, :visibility)
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
    db, created_at_after, created_at_before, result = params.values_at(
      :db,
      :created_at_after,
      :created_at_before,
      :result
    ).map(&:presence)

    submissions = user_submissions

    submissions = submissions.where(validations: {db: db.split(',')})                if db
    submissions = submissions.where(created_at: created_at_after..created_at_before) if created_at_after || created_at_before
    submissions = submissions.where(result: result.split(','))                       if result

    submissions
  end
end
