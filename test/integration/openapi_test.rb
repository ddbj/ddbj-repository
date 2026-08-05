require 'test_helper'

class OpenapiTest < ActionDispatch::IntegrationTest
  test 'openapi document is valid' do
    assert_is_valid_document skooma_openapi_schema
  end

  # The API now refuses a filter value outside the enum, so the schema's
  # copy of it is the contract clients read to know what is accepted. If
  # the two drift, a value the document advertises is answered with 400 —
  # and renaming an enum is exactly the change that starts that.
  {
    'Db'                       => -> { Submission.dbs.keys },
    'SubmissionOperationStatus' => -> { SubmissionRequest.statuses.keys }
  }.each do |name, model_values|
    test "#{name} in the schema matches the model" do
      document = YAML.safe_load(Rails.root.join('schema/openapi.yml').read, aliases: true)

      assert_equal model_values.call, document.dig('components', 'schemas', name, 'enum')
    end
  end
end
