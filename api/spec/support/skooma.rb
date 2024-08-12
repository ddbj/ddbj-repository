spec = Rails.root.join('../schema/openapi.yml')

RSpec.configure do |config|
  config.include Skooma::RSpec[spec, path_prefix: '/api'], type: :request
end

Skooma::BodyParsers.register 'multipart/form-data', ->(body, headers:) {
  Rack::Multipart::Parser.parse(
    StringIO.new(body),
    headers['Content-Length'].to_i,
    headers['Content-Type'],
    ->(*) { +'' },
    Rack::Multipart::Parser::BUFSIZE,
    Rack::Utils.default_query_parser,
  ).params
}
