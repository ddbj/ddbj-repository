require 'rambulance/exceptions_app'

Rambulance.setup do |config|
  config.rescue_responses = {
    # Listed even though it subclasses ActionController::BadRequest: the
    # lookup is by exact class name, so the parent's mapping is not
    # inherited. The subclassing is for Sentry, whose exclusion list does
    # match by ancestry — a client's bad filter value should be answered,
    # not reported as a fault of ours.
    'EnumFilterable::UnknownFilterValue'                    => :bad_request,
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
