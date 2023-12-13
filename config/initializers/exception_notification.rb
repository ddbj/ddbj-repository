ExceptionNotification.configure do |config|
  if recipients = ENV['EXCEPTION_RECIPIENTS'].presence
    config.add_notifier :email, **{
      sender_address:       ENV.fetch('EXCEPTION_SENDER'),
      exception_recipients: recipients.split(','),
      mailer_parent:        'ApplicationMailer'
    }
  end
end
