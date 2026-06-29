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

  # Falls back to a uid placeholder when Cloakman lookup is not available
  # (dev without cloakman setup; see [[project-dev-cloakman-setup]]).
  # Production / staging will resolve to the real email via the
  # admin/users CloakmanClient lookup once the integration is set up.
  def user_email_or_placeholder(user)
    user.try(:email).presence || "#{user.uid}@placeholder.invalid"
  end
end
