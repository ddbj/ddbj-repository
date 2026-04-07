require 'test_helper'

class ApiKeyTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"
  end

  test 'regenerate' do
    User.stub :generate_api_key, 'NEW_API_KEY' do
      post '/api/api_key/regenerate'
    end

    assert_conform_schema 200

    assert_equal 'NEW_API_KEY', response.parsed_body['api_key']
    assert_equal 'NEW_API_KEY', @user.reload.api_key
  end
end
