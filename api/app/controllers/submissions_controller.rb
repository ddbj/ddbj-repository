class SubmissionsController < ApplicationController
  include Pagination

  def index
    pagy, @submissions = pagy(submissions, page: params[:page])

    headers['Link'] = pagination_link_header(pagy, :submissions)
  rescue Pagy::OverflowError => e
    render json: {
      error: e.message
    }, status: :bad_request
  end

  def show
    @submission = submissions.find(params[:id].delete_prefix('X-'))
  end

  def create
    validation  = current_user.validations.find(params.require(:validation_id))
    @submission = Submission.create!(validation:)

    SubmitJob.perform_later @submission

    render status: :created
  end

  private

  def submissions
    current_user.submissions.includes(
      :validation => {
        :objs => {
          :file_attachment => :blob
        }
      }
    ).order(id: :desc, 'objs.id': :asc)
  end
end
