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
end
