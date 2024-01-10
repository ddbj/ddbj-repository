class SubmissionsController < ApplicationController
  include Pagination

  class UnprocessableEntity < StandardError; end

  def index
    pagy, @submissions = pagy(submissions.order(id: :desc), page: params[:page])

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
    validation = current_user.validations.find(params.require(:validation_id))

    ActiveRecord::Base.transaction do
      raise UnprocessableEntity, 'Validation failed: Validation is already submitted' if validation.submission

      @submission = validation.create_submission!
    end

    render status: :created
  end

  private

  def submissions
    current_user.submissions.includes(validation: {objs: :file_blob})
  end
end
