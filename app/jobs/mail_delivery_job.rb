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

  # Whether the submitter was told is decided here, because here is where
  # it becomes true. `deliver_later` only queues: an issuance that
  # recorded `sent` at enqueue time went on saying so after the retries
  # ran out and the message was dropped — the one claim the mail_status
  # column exists to stop making.
  #
  # Anything carrying an `issuance:` param gets the write-back; the rest
  # of the app's mail is unaffected.
  def perform(mailer, mail_method, delivery_method, args:, kwargs: nil, params: nil)
    super

    settle(params, 'sent')
  rescue Exception => e # rubocop:disable Lint/RescueException
    # Including the ones ActiveJob would otherwise take away silently:
    # a job killed mid-flight leaves a row claiming delivery for ever.
    settle(params, 'failed', "#{e.class}: #{e.message}")

    raise
  end

  private

  def settle(params, status, error_message = nil)
    issuance = params && params[:issuance]
    return unless issuance.is_a?(AccessionIssuance)

    # `update_columns`: this runs outside the issuance's own transaction
    # and must not fire callbacks or touch anything else about the row.
    issuance.update_columns(mail_status: status, error_message:, updated_at: Time.current)
  rescue ActiveRecord::RecordNotFound, ActiveRecord::StatementInvalid => e
    # The row can be gone by now. Losing the write is not a reason to
    # fail a delivery that otherwise succeeded.
    Rails.error.report(e, handled: true, source: 'mail_delivery_job.settle')
  end
end
