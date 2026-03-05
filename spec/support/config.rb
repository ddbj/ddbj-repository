RSpec.configure do |config|
  config.global_fixtures = :all

  config.include ActionDispatch::TestProcess::FixtureFile
  config.include ActiveSupport::Testing::TimeHelpers
  config.include FactoryBot::Syntax::Methods
  config.include RSpec::DefaultHttpHeader, type: :request
  config.include Rambulance::TestHelper
end
