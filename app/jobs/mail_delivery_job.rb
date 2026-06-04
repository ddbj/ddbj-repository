# Custom mail delivery job — same pattern as submission-mss. Subclass-and-
# replace lets us attach a mail-only retry policy without affecting other
# jobs (SyncBpJob, MigrationJob, etc.). Polynomial backoff on
# `Net::OpenTimeout` covers the mail1i transient timeouts that would
# otherwise drop the message permanently on first failure.
#
# Wired in via `config.action_mailer.delivery_job = 'MailDeliveryJob'`
# (config/application.rb).
class MailDeliveryJob < ActionMailer::MailDeliveryJob
  retry_on Net::OpenTimeout, wait: :polynomially_longer
end
