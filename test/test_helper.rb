ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'
require 'webmock/minitest'
require 'minitest/mock'
require 'minitest-default_http_header'

WebMock.disable_net_connect! allow_localhost: true

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

  # PathClassifier holds process-global memoised caches + structural-key
  # safety flags. Registry.stub blocks (and any other test-time rule
  # mutation) leave stale entries behind that would leak into subsequent
  # tests; clear before every test so each starts from the canonical
  # registry state.
  setup do
    DDBJRecord::Canonicalizer::PathClassifier.reset!
  end
end

class ActionDispatch::IntegrationTest
  include Skooma::Minitest[Rails.root.join('schema/openapi.yml'), path_prefix: '/api']
  include Rambulance::TestHelper

  teardown do
    OmniAuth.config.mock_auth[:keycloak] = nil
  end

  private

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
    OmniAuth.config.mock_auth[:keycloak] = OmniAuth::AuthHash.new(
      'provider' => 'keycloak',
      'uid'      => user.uid,

      'extra' => {
        'raw_info' => {
          'preferred_username'  => user.uid,
          'account_type_number' => user.admin? ? SessionsController::ADMIN_ACCOUNT_TYPE : 1
        }
      }
    )

    get '/auth/keycloak/callback'
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
