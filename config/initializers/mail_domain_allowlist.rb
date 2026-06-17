# Restrict outgoing mail to a configured set of allowed domains.
#
# Used by non-production envs (dev / staging) that import real D-way
# data: a curator click on "Issue accession" must not send mail to the
# real submitter at gmail/university/etc. while we are still
# verifying the import.
#
# Config: `mail_allowed_domains` in `config/app.yml`'s env block, as
# a YAML list. When unset (production) the interceptor is not
# registered and every recipient is delivered.
#
# Mechanism: an ActionMailer delivering-email interceptor mutates
# to/cc/bcc to only those addresses ending with one of the allowed
# domains. If nothing survives the filter the mail is suppressed via
# `perform_deliveries = false` so SMTP is never contacted.
class MailDomainAllowlistInterceptor
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

if (domains = Rails.application.config_for(:app).mail_allowed_domains.presence)
  ActionMailer::Base.register_interceptor MailDomainAllowlistInterceptor.new(domains)
end
