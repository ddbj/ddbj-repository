require 'test_helper'

class MessagesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"

    @submission_request = submission_requests(:bioproject) # owned by :alice
  end

  test 'GET index returns the thread chronologically and conforms to schema' do
    older = @submission_request.messages.create!(user: users(:bob), author_role: :curator, body: 'A')
    newer = @submission_request.messages.create!(user: @user,       author_role: :submitter, body: 'B')

    get submission_request_messages_path(@submission_request)

    assert_conform_schema 200
    assert_equal [older.id, newer.id], response.parsed_body.pluck('id')
  end

  # Reading is not dealing with it. Discharging the thread as a side
  # effect of rendering it took away the only reminder a submitter had
  # that they still owed an answer — and their curator saw nothing
  # either, because that queue tracks unread SUBMITTER messages.
  test 'GET index leaves the thread unread' do
    unread = @submission_request.messages.create!(user: users(:bob), author_role: :curator, body: 'pending')

    get submission_request_messages_path(@submission_request)

    assert_response :ok
    assert_nil unread.reload.read_at
    assert_includes SubmissionRequest.needs_submitter_action, @submission_request
  end

  # The two things that do discharge it: answering, and saying there is
  # nothing to answer.
  test 'replying marks the question read' do
    unread = @submission_request.messages.create!(user: users(:bob), author_role: :curator, body: 'q')

    post submission_request_messages_path(@submission_request),
         params:  {submission_message: {body: 'here you go'}}.to_json,
         headers: {'Content-Type' => 'application/json'}

    assert_response :created
    assert_not_nil unread.reload.read_at
    assert_not_includes SubmissionRequest.needs_submitter_action, @submission_request
  end

  test 'marking read discharges a note that needs no reply' do
    unread = @submission_request.messages.create!(user: users(:bob), author_role: :curator, body: 'FYI')

    post read_submission_request_messages_path(@submission_request)

    assert_response :no_content
    assert_not_nil unread.reload.read_at
    assert_not_includes SubmissionRequest.needs_submitter_action, @submission_request
  end

  test 'POST creates a submitter message and enqueues notify_curators' do
    @submission_request.messages.create!(user: users(:bob), author_role: :curator, body: 'q')

    assert_enqueued_emails 1 do
      assert_difference 'SubmissionMessage.count', 1 do
        post submission_request_messages_path(@submission_request),
             params:  {submission_message: {body: 'thanks, here is the data'}}.to_json,
             headers: {'Content-Type' => 'application/json'}
      end
    end

    assert_conform_schema 201
    msg = @submission_request.messages.submitter_role.last
    assert_equal 'thanks, here is the data', msg.body
    assert_equal @user,                      msg.user
  end

  test 'POST cannot reach another user request' do
    other = submission_requests(:biosample).tap { it.update_column(:user_id, users(:carol).id) }

    post submission_request_messages_path(other),
         params:  {submission_message: {body: 'hijack'}}.to_json,
         headers: {'Content-Type' => 'application/json'}

    assert_response :not_found
  end
end
