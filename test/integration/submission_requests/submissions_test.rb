require 'test_helper'

class SubmissionRequestsSubmissionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"
  end

  test 'create' do
    request = submission_requests(:one)

    attach_ddbj_record request
    request.update! status: :ready_to_apply

    Validation.create!(
      subject:     request,
      progress:    :finished,
      finished_at: Time.current
    )

    perform_enqueued_jobs do
      post submission_request_submission_path(request)
    end

    assert_conform_schema 204
  end
end
