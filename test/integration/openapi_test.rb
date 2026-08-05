require 'test_helper'

class OpenapiTest < ActionDispatch::IntegrationTest
  test 'openapi document is valid' do
    assert_is_valid_document skooma_openapi_schema
  end

  # The API now refuses a filter value outside the enum, so the schema's
  # copy of it is the contract clients read to know what is accepted. If
  # the two drift, a value the document advertises is answered with 400 —
  # and renaming an enum is exactly the change that starts that.
  # Both models, because both are filtered on: /submissions refuses by
  # Submission's enum and /submission_requests by SubmissionRequest's.
  # Checking one would let the other drift into refusing a value the
  # document still advertises.
  {
    'Db'                        => -> { [Submission.dbs.keys, SubmissionRequest.dbs.keys] },
    'SubmissionOperationStatus' => -> { [SubmissionRequest.statuses.keys] }
  }.each do |name, model_values|
    test "#{name} in the schema matches every model filtered by it" do
      document  = YAML.safe_load(Rails.root.join('schema/openapi.yml').read, aliases: true)
      published = document.dig('components', 'schemas', name, 'enum')

      model_values.call.each { assert_equal it, published }
    end
  end
end
