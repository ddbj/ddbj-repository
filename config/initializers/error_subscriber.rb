class ErrorSubscriber
  def report(error, handled:, severity:, context:, source: nil)
    Sentry.capture_exception error, extra: {handled:, severity:, context:, source:}
  end
end

Rails.error.subscribe ErrorSubscriber.new
