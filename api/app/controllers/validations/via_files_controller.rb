class Validations::ViaFilesController < ApplicationController
  include ViaFile

  def create
    request = create_request_from_params(current_user, params, purpose: 'validate')

    ValidateJob.perform_later request

    render json: {
      request: {
        id:  request.id,
        url: url_for(request)
      }
    }, status: :created
  end
end
