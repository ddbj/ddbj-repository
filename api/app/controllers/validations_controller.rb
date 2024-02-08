class ValidationsController < ApplicationController
  include Pagy::Backend
  include SearchValidations

  def index
    validations = search_validations_for_user(eager_load(current_user.validations))
    pagy, @validations = pagy(validations, page: params[:page])

    pagy_headers_merge pagy
  rescue Pagy::OverflowError => e
    render json: {
      error: e.message
    }, status: :bad_request
  end

  def show
    @validation = eager_load(accessible_validations).find(params[:id])
  end

  def destroy
    validation = accessible_validations.find(params[:id])

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

  def accessible_validations
    current_user.admin? ? Validation.all : current_user.validations
  end

  def eager_load(validations)
    validations.includes(:submission, :objs).merge(Obj.with_attached_file)
  end
end
