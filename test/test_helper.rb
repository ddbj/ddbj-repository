ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'
require 'webmock/minitest'
require 'minitest/mock'
require 'minitest-default_http_header'

WebMock.disable_net_connect! allow_localhost: true

# Every admin view links the compiled stylesheet, and Propshaft raises
# when it is missing — so a clean checkout fails with a hundred template
# errors that say nothing about assets.
#
# dartsass-rails hooks `db:test:prepare`, which CI runs as its own step
# and a developer running `bin/rails test:all` does not. Build it here
# when it is absent, which costs nothing on the runs where it is not.
unless Rails.root.join('app/assets/builds/admin.css').exist?
  require 'dartsass/runner'

  system(*Dartsass::Runner.dartsass_compile_command, exception: true)
end

OmniAuth.config.test_mode = true

Skooma::BodyParsers.register 'multipart/form-data', ->(body, headers:) {
  Rack::Multipart::Parser.parse(
    StringIO.new(body),
    headers['Content-Length'].to_i,
    headers['Content-Type'],
    ->(*) { +'' },
    Rack::Multipart::Parser::BUFSIZE,
    Rack::Utils.default_query_parser
  ).params
}

class ActiveSupport::TestCase
  set_fixture_class names: Taxdump::Name, nodes: Taxdump::Node

  fixtures :all

  def attach_ddbj_record(record)
    record.ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )
  end

  def attach_submission_files(submission)
    submission.ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    submission.flatfile_na.attach(
      io:           file_fixture('flatfile/example.flat').open,
      filename:     'example-na.flat',
      content_type: 'text/plain'
    )

    submission.flatfile_aa.attach(
      io:           file_fixture('flatfile/example.flat').open,
      filename:     'example-aa.flat',
      content_type: 'text/plain'
    )
  end

  def sign_in_as(user)
    mock_keycloak_auth(user)

    # Drive the admin-origin branch so the callback mints the session
    # cookie (the web branch is JWT-only and sets no session).
    get '/auth/keycloak/callback', env: {'omniauth.origin' => '/admin'}
  end

  # PathClassifier holds process-global memoised caches + structural-key
  # safety flags. Registry.stub blocks (and any other test-time rule
  # mutation) leave stale entries behind that would leak into subsequent
  # tests; clear before every test so each starts from the canonical
  # registry state.
  setup do
    DDBJRecord::Canonicalizer::PathClassifier.reset!
  end

  # SubmissionUpdate#patch is an ActiveStorage attachment. Fixture rows
  # are raw INSERTed so `validates :patch, attached: true` is bypassed;
  # tests that touch parsed_patch / download still need an attachment.
  # Attach a canned baseline patch to the one fixture row at setup so
  # individual tests don't have to remember.
  setup do
    update = submission_updates(:st26)
    next if update.patch.attached?

    update.patch.attach(
      io:           StringIO.new('[{"op":"add","path":"/title","value":"fixture"}]'),
      filename:     'patch.json',
      content_type: 'application/json'
    )
  end

  # Cloakman is the system of record for contact details, so anything that
  # resolves a recipient (User#email) or renders a profile goes through it.
  # Pass an empty `profiles` with explicit `uids:` to model "no profile".
  # The identity Keycloak would return. Shared with the system suite,
  # which signs in through the form rather than the callback — two copies
  # would let one of them keep signing in as a general account long after
  # the shape changed, and every admin assertion would fail obscurely.
  def mock_keycloak_auth(user)
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
  end

  # Cloakman profiles the fixtures correspond to, so the two suites agree
  # on what DDBJ Account would say about them.
  CLOAKMAN_PROFILES = {
    alice: {uid: 'alice', full_name: 'Alice Liddell', email: 'alice@example.com', organization: 'Wonderland',   account_type_number: 'general'},
    bob:   {uid: 'bob',   full_name: 'Bob Builder',   email: 'bob@example.com',   organization: 'Construction', account_type_number: 'general'},
    carol: {uid: 'carol', full_name: 'Carol King',    email: 'carol@example.com', organization: 'Music',        account_type_number: 'general'},
    dave:  {uid: 'dave',  full_name: 'Dave Curator',  email: 'dave@example.com',  organization: 'DDBJ',         account_type_number: 'general'}
  }.freeze

  def cloakman_profile(name) = CLOAKMAN_PROFILES.fetch(name)

  # Every deployed environment restricts outgoing mail while sending to
  # real submitters is switched off. A real interceptor rather than a
  # stubbed domain list, so the matching a test relies on is the matching
  # that runs in production.
  #
  # It is not registered with ActionMailer, so this restricts what
  # `delivers_to?` answers and not what the test adapter records: a mail
  # some other path enqueues still counts as delivered here. Enough for
  # code that asks before sending, and not a way to test suppression.
  def restrict_mail_to(*domains)
    MailDomainAllowlistInterceptor.stub(:registered, MailDomainAllowlistInterceptor.new(domains)) do
      yield
    end
  end

  # Cloakman's free-text search, which the Users screen widens its uid
  # match with.
  def stub_cloakman_search(query, profiles)
    stub_request(:get, 'http://cloakman.example.com/api/users')
      .with(query: {query:})
      .to_return(
        status:  200,
        body:    profiles.to_json,
        headers: {'Content-Type' => 'application/json'}
      )
  end

  def stub_cloakman_lookup(profiles, uids: profiles.map { it[:uid] })
    stub_request(:get, 'http://cloakman.example.com/api/users/lookup')
      .with(query: {uids:})
      .to_return(
        status:  200,
        body:    profiles.to_json,
        headers: {'Content-Type' => 'application/json'}
      )
  end
end

class ActionDispatch::IntegrationTest
  include Skooma::Minitest[Rails.root.join('schema/openapi.yml'), path_prefix: '/api']
  include Rambulance::TestHelper

  teardown do
    OmniAuth.config.mock_auth[:keycloak] = nil
  end
end
