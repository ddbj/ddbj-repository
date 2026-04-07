require 'test_helper'

class SubmissionUpdatesSubmissionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"
  end

  test 'create' do
    update = submission_updates(:one)

    attach_ddbj_record update
    update.update! status: :ready_to_apply

    Validation.create!(
      subject:     update,
      progress:    :finished,
      finished_at: Time.current
    )

    perform_enqueued_jobs do
      patch submission_update_submission_path(update)
    end

    assert_conform_schema 204
  end
end
