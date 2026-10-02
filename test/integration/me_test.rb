require 'test_helper'

class MeTest < ActionDispatch::IntegrationTest
  setup do
    default_headers['Authorization'] = "Bearer #{users(:alice).api_key}"
  end

  test 'show' do
    get '/api/me'

    assert_conform_schema 200
  end

  # What the web client offers is what this says, so the screen and the
  # server open BioProject and BioSample together.
  test 'says which databases take submissions here' do
    get '/api/me'

    assert_conform_schema 200
    assert_equal %w[st26 bioproject biosample], response.parsed_body['submittable_dbs'], 'DRA is checked, but not yet applied'

    DDBJValidatorClient.stub(:configured?, false) { get '/api/me' }

    assert_conform_schema 200
    assert_equal %w[st26], response.parsed_body['submittable_dbs']
  end
end
