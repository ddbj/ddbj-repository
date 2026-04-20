ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'
require 'webmock/minitest'
require 'minitest/mock'
require 'minitest-default_http_header'

WebMock.disable_net_connect! allow_localhost: true

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
end

class ActionDispatch::IntegrationTest
  include Skooma::Minitest[Rails.root.join('schema/openapi.yml'), path_prefix: '/api']
  include Rambulance::TestHelper

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
end
