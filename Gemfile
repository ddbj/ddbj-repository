source 'https://rubygems.org'

gem 'rails', '~> 8.1.2'

gem 'active_storage_validations'
gem 'aws-sdk-s3'
gem 'bootsnap', require: false
gem 'diff-lcs'
gem 'image_processing'
gem 'jb'
gem 'json'
gem 'jwt'
gem 'kamal', require: false
gem 'mission_control-jobs'
gem 'omniauth_openid_connect'
gem 'pagy'
gem 'pg'
gem 'propshaft' # mission_control-jobs
gem 'puma'
gem 'rack-cors'
gem 'rambulance'
gem 'sentry-rails'
gem 'solid_queue'
gem 'thruster'

group :development do
  gem 'brakeman', require: false
  gem 'debug', require: 'debug/prelude', group: :test
  gem 'rubocop-rails-omakase', require: false
end

group :test do
  gem 'factory_bot_rails', group: :development
  gem 'rspec-default_http_header'
  gem 'rspec-rails', group: :development
  gem 'skooma'
  gem 'webmock', require: 'webmock/rspec'
end
