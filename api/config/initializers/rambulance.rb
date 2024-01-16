require 'rambulance/exceptions_app'

Rambulance.setup do |config|
  config.rescue_responses = {
    'Validations::FilesController::NotFound'      => :not_found,
    'Validations::ViaFilesController::BadRequest' => :bad_request
  }
end

class Rambulance::ExceptionsApp
  before_action do
    request.format = :json
  end
end
