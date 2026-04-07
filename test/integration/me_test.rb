require 'test_helper'

class MeTest < ActionDispatch::IntegrationTest
  setup do
    default_headers['Authorization'] = "Bearer #{users(:alice).api_key}"
  end

  test 'show' do
    get '/api/me'

    assert_conform_schema 200
  end
end
