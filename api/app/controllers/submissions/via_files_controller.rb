class Submissions::ViaFilesController < ApplicationController
  include ViaFile

  def create
    request = create_request_from_params(current_user, params, purpose: 'submit')

    SubmitJob.perform_later request

    render json: {
      request: {
        id:  request.id,
        url: url_for(request)
      }
    }, status: :created
  end
end
