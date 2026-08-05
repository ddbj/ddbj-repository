# Restrict outgoing mail to a configured set of allowed domains.
#
# Every deployed environment carries this, production included: the
# curator screens can issue accessions and answer messages, and both
# mail the submitter. Until sending to real submitters is deliberately
# switched on, the safe default is that only we receive it — a click on
# "Issue accession" against imported D-way data must not reach a real
# submitter at gmail/university/etc.
#
# Config: `mail_allowed_domains` in `config/app.yml`'s env block, as a
# YAML list. Removing it is what turns real mail on; the interceptor is
# then not registered and every recipient is delivered.
#
# Mechanism: an ActionMailer delivering-email interceptor mutates
# to/cc/bcc to only those addresses ending with one of the allowed
# domains. If nothing survives the filter the mail is suppressed via
# `perform_deliveries = false` so SMTP is never contacted.
class MailDomainAllowlistInterceptor
  # What is actually registered, for the screens that need to say so.
  # Read from here rather than from the config, so a banner promising a
  # restriction cannot outlive the interceptor that enforces it.
  class << self
    attr_accessor :domains
  end

  def initialize(domains)
    @domains = domains.map { it.downcase.delete_prefix('@') }
  end

  def delivering_email(mail)
    original = (Array(mail.to) + Array(mail.cc) + Array(mail.bcc))

    mail.to  = filter(mail.to)
    mail.cc  = filter(mail.cc)
    mail.bcc = filter(mail.bcc)

    survivors = (Array(mail.to) + Array(mail.cc) + Array(mail.bcc))

    if survivors.empty?
      mail.perform_deliveries = false
      Rails.logger.info "[mail_allowlist] suppressed delivery (no recipient matched @#{@domains.join(', @')}): #{original.join(', ')}"
    elsif survivors.size < original.size
      dropped = original - survivors
      Rails.logger.info "[mail_allowlist] filtered #{dropped.size} recipient(s) outside @#{@domains.join(', @')}: #{dropped.join(', ')}"
    end
  end

  private

  def filter(addresses)
    Array(addresses).select {|addr|
      @domains.any? { addr.downcase.end_with?("@#{it}") }
    }
  end
end

# Defer the actual registration to after_initialize: touching
# ActionMailer::Base at top-level forces ActionMailer to resolve
# config.action_mailer.delivery_job ('MailDeliveryJob') before
# Zeitwerk has wired up app/jobs/, which crashes `bin/rails db:prepare`
# with `uninitialized constant MailDeliveryJob`.
Rails.application.config.after_initialize do
  if (domains = Rails.application.config_for(:app).mail_allowed_domains.presence)
    interceptor = MailDomainAllowlistInterceptor.new(domains)

    MailDomainAllowlistInterceptor.domains = domains

    ActionMailer::Base.register_interceptor interceptor
  end
end
