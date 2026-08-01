require 'test_helper'

class AdminMessagesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:bob)
    @submission_request = submission_requests(:bioproject)
  end

  test 'POST creates a curator message and enqueues notify_submitter' do
    assert_enqueued_emails 1 do
      assert_difference 'SubmissionMessage.count', 1 do
        post admin_submission_request_messages_path(@submission_request),
             params: {submission_message: {body: 'Please clarify the strain.'}}
      end
    end

    assert_redirected_to messages_admin_submission_request_path(@submission_request)
    msg = @submission_request.messages.last
    assert_equal 'Please clarify the strain.', msg.body
    assert_equal 'curator',                    msg.author_role
    assert_equal users(:bob),                  msg.user
  end

  test 'POST rejects empty body without creating a row or enqueueing a mail' do
    assert_no_enqueued_emails do
      assert_no_difference 'SubmissionMessage.count' do
        post admin_submission_request_messages_path(@submission_request),
             params: {submission_message: {body: '   '}}
      end
    end

    assert_redirected_to messages_admin_submission_request_path(@submission_request)
    assert_match(/Write something or attach a file/, flash[:alert])
  end

  test 'POST requires admin auth' do
    sign_in_as users(:carol)
    post admin_submission_request_messages_path(@submission_request), params: {submission_message: {body: 'x'}}

    assert_response :forbidden
  end
end
