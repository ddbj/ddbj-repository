require 'test_helper'

class SubmissionUpdatesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"
  end

  test 'show' do
    update = submission_updates(:st26)

    attach_ddbj_record update
    attach_submission_files update.submission

    get submission_update_path(db: 'st26', id: update.id)

    assert_conform_schema 200
  end
end
