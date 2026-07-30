class ApplicationMailer < ActionMailer::Base
  layout 'mailer'

  default from: email_address_with_name('repo@ddbj.nig.ac.jp', 'DDBJ Repository')

  # Mirror submission-mss: non-production mail subjects get a visible
  # environment prefix so a curator / submitter inbox doesn't confuse a
  # staging / dev delivery with the production one.
  after_action do
    mail.subject.prepend '[Staging] ' if Rails.env.staging?
    mail.subject.prepend '[Dev] '     if Rails.env.dev?
  end

  private

  # `User#email` is our copy of the Cloakman address, refreshed at login and
  # by SyncUserEmailsJob. Blank means the address is genuinely unknown (an
  # account that has never logged in, with nothing in Cloakman either), and
  # there is nothing useful to do with that: a synthesised `.invalid`
  # recipient only converts the problem into a bounce. So callers return
  # without calling `mail`, which makes the action a no-op — Rails hands
  # back an empty Mail::Message and `deliver_later` does nothing.
  def recipient_for(user)
    return user.email if user.email.present?

    Rails.logger.info "[mailer] no known address for #{user.uid} — skipping #{self.class.name}##{action_name}"

    nil
  end
end
