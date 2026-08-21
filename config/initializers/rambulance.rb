require 'rambulance/exceptions_app'

Rambulance.setup do |config|
  config.rescue_responses = {
    'ApplicationController::Forbidden'             => :forbidden,
    'ApplicationController::UnprocessableContent'  => :unprocessable_content,

    # Losing a race is not a fault. Two people inviting the same address,
    # or one person pressing Add twice, land on a unique index; writing a
    # row whose parent was deleted a moment earlier lands on a foreign
    # key. Both answers are "that is no longer possible", which is what
    # the caller would have been told a moment either side of it.
    'ActiveRecord::RecordNotUnique'                => :unprocessable_content,
    'ActiveRecord::InvalidForeignKey'              => :unprocessable_content,

    # Listed even though it subclasses ActionController::BadRequest: the
    # lookup is by exact class name, so the parent's mapping is not
    # inherited. The subclassing is for Sentry, whose exclusion list does
    # match by ancestry — a client's bad filter value should be answered,
    # not reported as a fault of ours.
    'EnumFilterable::UnknownFilterValue'           => :bad_request,

    # A signed id that does not verify is a bad request, not a fault of
    # ours: it is a client sending something Active Storage did not mint,
    # which is exactly what the message controllers say they refuse when
    # they check the shape of `files`.
    'ActiveSupport::MessageVerifier::InvalidSignature' => :bad_request,

    'Validation::UnprocessableContent'             => :unprocessable_content
  }
end

class Rambulance::ExceptionsApp
  before_action do
    request.format = :json
  end
end
