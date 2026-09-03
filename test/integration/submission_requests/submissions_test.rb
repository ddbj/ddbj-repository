require 'test_helper'

class SubmissionRequestsSubmissionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"
  end

  test 'create' do
    request = submission_requests(:st26)

    attach_ddbj_record request
    request.update! status: :ready_to_apply

    # The fixture already gives this request a validation, dated 2024. A
    # second row is not a state the validator produces — it creates one
    # and updates it — and a submission is sent on the strength of a
    # current check, so what this test needs is for that one to be
    # current.
    request.validation.update!(progress: :finished, finished_at: Time.current)

    perform_enqueued_jobs do
      post submission_request_submission_path(submission_request_id: request.id)
    end

    assert_conform_schema 204
  end
end
