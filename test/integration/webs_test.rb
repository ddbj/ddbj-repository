require 'test_helper'

class WebsTest < ActionDispatch::IntegrationTest
  test 'serves the SPA shell with the runtime config injected' do
    get '/web/'

    assert_response :success
    assert_select 'meta[name=?]', 'sentry-dsn'
    assert_select 'meta[name=?][content=?]', 'sentry-environment', 'test'
  end

  test 'serves the shell for the bare mount point and client-side routes' do
    # Ember's rootURL is /web/, but a trailing slash is optional in routing and Ember
    # normalizes /web to /web/ on the client, so both must reach the shell.
    ['/web', '/web/submissions'].each do |path|
      get path

      assert_response :success, "expected #{path} to serve the shell"
      assert_select 'meta[name=?][content=?]', 'sentry-environment', 'test'
    end
  end

  test 'injects the configured Sentry DSN into the shell' do
    config = ActiveSupport::OrderedOptions.new
    config.sentry_dsn = 'https://public@sentry.example.com/1'

    Rails.application.stub :config_for, ->(*) { config } do
      get '/web/'
    end

    assert_select 'meta[name=?][content=?]', 'sentry-dsn', 'https://public@sentry.example.com/1'
  end
end
