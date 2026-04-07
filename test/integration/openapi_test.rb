require 'test_helper'

class OpenapiTest < ActionDispatch::IntegrationTest
  test 'openapi document is valid' do
    assert_is_valid_document skooma_openapi_schema
  end
end
