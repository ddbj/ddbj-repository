class Admin::ValidationsController < ApplicationController
  include Pagy::Backend
  include SearchValidations

  def index
    validations = search_validations_for_admin(Validation.all)
    pagy, @validations = pagy(validations, page: params[:page])

    pagy_headers_merge pagy
  rescue Pagy::OverflowError => e
    render json: {
      error: e.message
    }, status: :bad_request
  end
end
