require 'test_helper'

class SubmissionUpdatesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"
  end

  test 'show' do
    update = submission_updates(:one)

    attach_ddbj_record update
    attach_submission_files update.submission

    get submission_update_path(update)

    assert_conform_schema 200
  end
end
