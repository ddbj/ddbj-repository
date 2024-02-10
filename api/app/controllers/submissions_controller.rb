class SubmissionsController < ApplicationController
  include Pagy::Backend

  def index
    submissions = user_submissions.order(id: :desc)

    pagy, @submissions = pagy(submissions, page: params[:page])

    pagy_headers_merge pagy
  rescue Pagy::OverflowError => e
    render json: {
      error: e.message
    }, status: :bad_request
  end

  def show
    @submission = user_submissions.find(params[:id].delete_prefix('X-'))
  end

  def create
    validation  = current_user.validations.find(params.require(:validation_id))
    @submission = Submission.create!(validation:)

    SubmitJob.perform_later @submission

    render status: :created
  end

  private

  def user_submissions
    current_user.submissions.includes(
      :validation => [
        :user,

        :objs => {
          :file_attachment => :blob
        }
      ]
    )
  end
end
