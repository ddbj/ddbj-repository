require 'exception_notification/rails'
require 'exception_notification/sidekiq'

ExceptionNotification.configure do |config|
  if recipients = ENV['EXCEPTION_RECIPIENTS'].presence
    config.add_notifier :email, **{
      sender_address:       ENV.fetch('EXCEPTION_SENDER'),
      exception_recipients: recipients.split(','),
      mailer_parent:        'ApplicationMailer'
    }
  end

  config.ignore_if do
    !recipients
  end

  config.ignored_exceptions = ExceptionNotifier.ignored_exceptions + %w(
    FileDownload::NotFound
    ViaFile::BadRequest
  )
end
