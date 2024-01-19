class ValidationsController < ApplicationController
  include Pagination

  def index
    pagy, @validations = pagy(validations, page: params[:page])

    headers['Link'] = pagination_link_header(pagy, :validations)
  rescue Pagy::OverflowError => e
    render json: {
      error: e.message
    }, status: :bad_request
  end

  def show
    @validation = validations.find(params[:id])
  end

  def destroy
    validation = validations.find(params[:id])

    if validation.finished? || validation.canceled?
      render json: {
        error: "Validation has been #{validation.progress}."
      }, status: :conflict
    else
      validation.update! progress: 'canceled', finished_at: Time.current

      render json: {
        message: 'Validation canceled successfully.'
      }
    end
  end

  private

  def validations
    current_user.validations.includes(:submission, :objs => :file_blob).order(id: :desc, 'objs.id': :asc)
  end
end
