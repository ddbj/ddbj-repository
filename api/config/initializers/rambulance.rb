require 'rambulance/exceptions_app'

Rambulance.setup do |config|
  config.rescue_responses = {
    'FileDownload::NotFound' => :not_found,
    'ViaFile::BadRequest'    => :bad_request
  }
end

class Rambulance::ExceptionsApp
  before_action do
    request.format = :json
  end
end
