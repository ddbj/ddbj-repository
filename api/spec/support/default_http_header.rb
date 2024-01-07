RSpec.configure do |config|
  config.include RSpec::DefaultHttpHeader, type: :request

  config.before :example, type: :request, authorized: true do
    default_headers[:Authorization] = 'Bearer API_KEY'
  end
end
