source "https://rubygems.org"

gem "rails", "~> 8.0.1"

gem "aws-sdk-s3"
gem "base62-rb"
gem "bootsnap", require: false
gem "fetch-api"
gem "jb"
gem "json"
gem "kamal", require: false
gem "metabobank_tools", github: "ddbj/metabobank_tools"
gem "noodles_gff", path: "noodles_gff-rb"
gem "openid_connect"
gem "pagy"
gem "parallel"
gem "pg"
gem "puma"
gem "rack-cors"
gem "rambulance"
gem "retriable"
gem "sentry-rails"
gem "solid_queue"
gem "submission-excel2xml", github: "ddbj/submission-excel2xml"
gem "thruster"

group :development do
  gem "brakeman", require: false
  gem "debug", require: "debug/prelude", group: :test
  gem "rubocop-rails-omakase", require: false
end

group :test do
  gem "factory_bot_rails", group: :development
  gem "rails-controller-testing"
  gem "rspec-default_http_header"
  gem "rspec-rails", group: :development
  gem "skooma"
  gem "test-prof"
  gem "webmock", require: "webmock/rspec"
end
