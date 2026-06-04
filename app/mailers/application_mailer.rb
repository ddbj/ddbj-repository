class ApplicationMailer < ActionMailer::Base
  layout 'mailer'

  default from: email_address_with_name('repo@ddbj.nig.ac.jp', 'DDBJ Repository')

  # Mirror submission-mss: staging mail subjects get a visible `[Staging]`
  # prefix so a curator / submitter inbox doesn't confuse a staging
  # delivery with the production one.
  after_action do
    mail.subject.prepend '[Staging] ' if Rails.env.staging?
  end
end
