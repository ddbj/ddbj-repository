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
  # restriction cannot outlive the interceptor that enforces it — and it
  # is the normalised list, so a config entry written `@DDBJ.nig.ac.jp`
  # is announced as the address it actually matches.
  class << self
    attr_accessor :registered

    def domains = registered&.domains

    # Whether a given address would actually be delivered to. Answered by
    # the object that does the filtering rather than by a screen reading
    # the config, so a page saying "not delivered" cannot drift from what
    # happens — and unrestricted means everything goes, which is the
    # answer when nothing is registered.
    def delivers_to?(address) = registered.nil? || registered.allows?(address)
  end

  attr_reader :domains

  def initialize(domains)
    @domains = domains.map { it.downcase.delete_prefix('@') }
  end

  # Callers reach this from two directions and hand over two different
  # things. `delivering_email` passes `mail.to`, which Mail has already
  # parsed down to the addr-spec; a screen asking about a submitter
  # passes whatever is stored on the User, which may carry a display
  # name or trailing whitespace. Unparsed, `Foo <foo@ddbj.nig.ac.jp>`
  # ends with `>` and matches nothing — and since a false answer now
  # skips the send rather than merely reporting on it, that would be a
  # silent non-delivery to somebody the allowlist allows.
  def allows?(address)
    addr = address.to_s.strip.downcase
    addr = addr[/<([^>]*)>\z/, 1] || addr

    addr.present? && @domains.any? { addr.end_with?("@#{it}") }
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

  def filter(addresses) = Array(addresses).select { allows?(it) }
end

# Defer the actual registration to after_initialize: touching
# ActionMailer::Base at top-level forces ActionMailer to resolve
# config.action_mailer.delivery_job ('MailDeliveryJob') before
# Zeitwerk has wired up app/jobs/, which crashes `bin/rails db:prepare`
# with `uninitialized constant MailDeliveryJob`.
Rails.application.config.after_initialize do
  if (domains = Rails.application.config_for(:app).mail_allowed_domains.presence)
    interceptor = MailDomainAllowlistInterceptor.new(domains)

    MailDomainAllowlistInterceptor.registered = interceptor

    ActionMailer::Base.register_interceptor interceptor
  end
end
