class ErrorSubscriber
  def report(error, handled:, severity:, context:, source: nil)
    ExceptionNotifier.notify_exception error, data: {handled:, severity:, context:, source:}
  end
end

Rails.error.subscribe ErrorSubscriber.new
