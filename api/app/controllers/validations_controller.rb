class ValidationsController < ApplicationController
  include Pagy::Backend
  include SearchValidations

  def index
    validations = search_validations_for_user(user_validations)
    pagy, @validations = pagy(validations, page: params[:page])

    pagy_headers_merge pagy
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
