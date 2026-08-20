Sentry.init do |config|
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  config.dsn                = Rails.application.config_for(:app).sentry_dsn

  # A refusal we wrote the words for is the system working. "Only the
  # owner can rename a set" is not a fault to be woken up about, and
  # the exclusion list matches by ancestry — which is why
  # EnumFilterable::UnknownFilterValue subclasses ActionController::
  # BadRequest rather than being listed here.
  config.excluded_exceptions += %w[
    ApplicationController::Forbidden
    ApplicationController::UnprocessableContent
    ActiveRecord::RecordNotUnique
    ActiveRecord::InvalidForeignKey
  ]
end
