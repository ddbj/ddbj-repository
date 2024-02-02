class ValidationsController < ApplicationController
  include Pagination

  def index
    validations = user_validations.order(id: :desc)

    pagy, @validations = pagy(validations, page: params[:page])

    headers['Link'] = pagination_link_header(pagy, :validations)
  rescue Pagy::OverflowError => e
    render json: {
      error: e.message
    }, status: :bad_request
  end

  def show
    @validation = user_validations.find(params[:id])
  end

  def destroy
    validation = user_validations.find(params[:id])

    if validation.finished? || validation.canceled?
      render json: {
        error: "Validation has been #{validation.progress}."
      }, status: :unprocessable_entity
    else
      validation.update! progress: 'canceled', finished_at: Time.current

      render json: {
        message: 'Validation canceled successfully.'
      }
    end
  end

  private

  def user_validations
    current_user.validations.includes(:submission, :objs).merge(Obj.with_attached_file)
  end
end
