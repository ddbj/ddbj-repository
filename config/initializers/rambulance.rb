require 'rambulance/exceptions_app'

Rambulance.setup do |config|
  config.rescue_responses = {
    'Validation::UnprocessableContent'                      => :unprocessable_content,
    'Validations::FilesController::NotFound'                => :not_found,
    'Validations::ViaFilesController::UnprocessableContent' => :unprocessable_content
  }
end

class Rambulance::ExceptionsApp
  before_action do
    request.format = :json
  end
end
