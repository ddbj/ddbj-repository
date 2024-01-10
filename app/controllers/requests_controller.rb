class RequestsController < ApplicationController
  include Pagination

  def index
    pagy, @requests = pagy(requests.order(id: :desc), page: params[:page])

    headers['Link'] = pagination_link_header(pagy, :requests)
  rescue Pagy::OverflowError => e
    render json: {
      error: e.message
    }, status: :bad_request
  end

  def show
    @request = requests.find(params[:id])
  end

  def destroy
    request = requests.find(params[:id])

    if request.finished? || request.canceled?
      render json: {
        error: "Request already #{request.status}."
      }, status: :conflict
    else
      request.canceled!

      render json: {
        message: 'Request canceled successfully.'
      }
    end
  end

  private

  def requests
    current_user.requests.includes(:submission, :objs => :file_blob)
  end
end
