require 'test_helper'

class SubmissionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"

    @submission = submissions(:one)

    attach_submission_files @submission
    attach_ddbj_record submission_updates(:one)
  end

  test 'index' do
    get submissions_path

    assert_conform_schema 200

    assert_includes response.parsed_body.pluck('id'), @submission.id
  end

  test 'show' do
    get submission_path(@submission)

    assert_conform_schema 200
    assert_equal @submission.id, response.parsed_body['id']
  end
end
