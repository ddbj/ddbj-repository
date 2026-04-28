require 'test_helper'

class SubmissionsUpdatesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"

    @submission = submissions(:st26)

    attach_submission_files @submission
    attach_ddbj_record submission_updates(:st26)
  end

  test 'create' do
    blob = ActiveStorage::Blob.create_and_upload!(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    post submission_updates_path(db: 'st26', submission_id: @submission.id), params: {
      submission_update: {
        ddbj_record: blob.signed_id
      }
    }, as: :json

    assert_conform_schema 202
  end
end
