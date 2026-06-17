require 'test_helper'

class MailDomainAllowlistInterceptorTest < ActiveSupport::TestCase
  test 'keeps recipients whose domain is on the allowlist' do
    interceptor = MailDomainAllowlistInterceptor.new(%w[ddbj.nig.ac.jp ursm.jp])
    mail        = Mail.new(to: %w[curator@ddbj.nig.ac.jp outsider@example.com], cc: 'admin@ursm.jp')

    interceptor.delivering_email(mail)

    assert_equal %w[curator@ddbj.nig.ac.jp],         mail.to
    assert_equal %w[admin@ursm.jp],                  mail.cc
    assert mail.perform_deliveries
  end

  test 'suppresses delivery when no recipient survives the filter' do
    interceptor = MailDomainAllowlistInterceptor.new(%w[ddbj.nig.ac.jp])
    mail        = Mail.new(to: 'outsider@example.com')

    interceptor.delivering_email(mail)

    assert_equal [], mail.to
    refute mail.perform_deliveries
  end

  test 'matches case-insensitively' do
    interceptor = MailDomainAllowlistInterceptor.new(%w[DDBJ.NIG.AC.JP])
    mail        = Mail.new(to: 'Curator@ddbj.nig.ac.jp')

    interceptor.delivering_email(mail)

    assert_equal ['Curator@ddbj.nig.ac.jp'], mail.to
  end

  test 'logs which recipients were dropped' do
    interceptor = MailDomainAllowlistInterceptor.new(%w[ddbj.nig.ac.jp])
    mail        = Mail.new(to: %w[curator@ddbj.nig.ac.jp outsider@example.com])

    log = capture_log { interceptor.delivering_email(mail) }

    assert_match(/filtered 1 recipient/,  log)
    assert_match(/outsider@example\.com/, log)
  end

  test 'logs when delivery is fully suppressed' do
    interceptor = MailDomainAllowlistInterceptor.new(%w[ddbj.nig.ac.jp])
    mail        = Mail.new(to: 'outsider@example.com')

    log = capture_log { interceptor.delivering_email(mail) }

    assert_match(/suppressed delivery/,   log)
    assert_match(/outsider@example\.com/, log)
  end

  private

  def capture_log
    io     = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    original = Rails.logger

    Rails.logger = logger
    yield
    io.string
  ensure
    Rails.logger = original
  end
end
