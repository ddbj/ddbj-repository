require_relative 'uploaded_file'

RSpec.configure do |config|
  config.include ActionDispatch::TestProcess::FixtureFile
  config.include ActiveSupport::Testing::TimeHelpers
  config.include FactoryBot::Syntax::Methods
  config.include Rambulance::TestHelper
  config.include UploadedFile
end
