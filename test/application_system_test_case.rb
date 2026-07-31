require 'test_helper'
require 'capybara/rails'
require 'capybara/minitest'

# Tests written from the outside: visit a page, read what is on it, press
# what a curator would press.
#
# Integration tests address routes directly, which makes them blind to
# everything between the screen and the request — a button whose label was
# eaten by its value, a checkbox with no hidden partner so it could be
# ticked but never unticked, a `formmethod` overridden by the form's own
# `_method`, a `button_to` nested inside another form and therefore
# silently reassigned to it. Every one of those shipped past a green
# integration suite in this repo, and each was a control that did the
# wrong thing while its endpoint did the right one.
#
# So: anything a person does through a screen belongs here. Integration
# tests keep what has no screen — the JSON API, and server-side rules
# asserted directly.
#
# NOTE: subclasses inherit ActionDispatch::IntegrationTest's own
# `@request`, so naming an instance variable that shadows it silently
# hands your test a Rack request instead of the record you meant. `@req`
# is the convention here.
class ApplicationSystemTestCase < ActionDispatch::IntegrationTest
  include Capybara::DSL
  include Capybara::Minitest::Assertions

  # rack_test by default: no browser, no JavaScript, and it still exercises
  # the whole form → route → response path, which is where the misses
  # above lived. JavaScriptSystemTestCase below is for screens whose
  # behaviour genuinely is JavaScript.
  DRIVER = :rack_test

  # Find controls by their accessible name, so `aria-label` counts as a
  # label. Several of these screens label icon-ish controls that way — a
  # row checkbox reading "Select #1482" — and a test that cannot see the
  # accessible name ends up matching on CSS, which is the same as not
  # testing the label at all.
  Capybara.enable_aria_label = true

  setup do
    Capybara.current_driver = self.class::DRIVER
    Capybara.app_host       = nil
  end

  teardown do
    Capybara.reset_sessions!
    Capybara.use_default_driver
  end

  # Signing in the way a curator does: ask for a page, get bounced to the
  # login screen, press the button, arrive at what you asked for. The
  # alternative — reaching into the OmniAuth callback — would skip the
  # very form whose hidden `origin` field is what brings you back, and
  # that field is exactly the sort of thing this file exists to cover.
  def sign_in_as(user, at: admin_root_path)
    OmniAuth.config.mock_auth[:keycloak] = OmniAuth::AuthHash.new(
      'provider' => 'keycloak',
      'uid'      => user.uid,

      'extra' => {
        'raw_info' => {
          'preferred_username'  => user.uid,
          'account_type_number' => CloakmanClient::ACCOUNT_TYPES.key(user.admin? ? CloakmanClient::STAFF_ACCOUNT_TYPE : 'general')
        }
      }
    )

    visit at
    click_button 'Log in with DDBJ Account'
  end
end

# For screens whose behaviour is JavaScript — a preview that follows the
# field being typed into, a counter that tracks checkboxes, a collapse
# that opens. capybara-simulated runs the real Turbo / Stimulus in
# process, so these stay fast enough to live in the same suite.
class JavaScriptSystemTestCase < ApplicationSystemTestCase
  DRIVER = :simulated
end
