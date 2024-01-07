class SubmissionsController < ApplicationController
  include Pagination

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

  private

  def submissions
    current_user.submissions.includes(request: {objs: :file_blob})
  end
end
