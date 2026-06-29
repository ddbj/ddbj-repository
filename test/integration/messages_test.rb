require 'test_helper'

class MessagesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"

    @submission = submissions(:bioproject) # owned by :alice
  end

  test 'GET index returns the thread chronologically and conforms to schema' do
    older = @submission.messages.create!(user: users(:bob), author_role: :curator, body: 'A')
    newer = @submission.messages.create!(user: @user,       author_role: :submitter, body: 'B')

    get submission_messages_path(@submission)

    assert_conform_schema 200
    assert_equal [older.id, newer.id], response.parsed_body.pluck('id')
  end

  test 'GET index marks unread curator messages as read by the submitter' do
    unread = @submission.messages.create!(user: users(:bob), author_role: :curator, body: 'pending')

    get submission_messages_path(@submission)

    assert_response :ok
    assert_not_nil unread.reload.read_at
  end

  test 'POST creates a submitter message and enqueues notify_curators' do
    @submission.messages.create!(user: users(:bob), author_role: :curator, body: 'q')

    assert_enqueued_emails 1 do
      assert_difference 'SubmissionMessage.count', 1 do
        post submission_messages_path(@submission),
             params:  {submission_message: {body: 'thanks, here is the data'}}.to_json,
             headers: {'Content-Type' => 'application/json'}
      end
    end

    assert_conform_schema 201
    msg = @submission.messages.submitter_role.last
    assert_equal 'thanks, here is the data', msg.body
    assert_equal @user,                      msg.user
  end

  test 'POST cannot reach another user submission' do
    other = submissions(:biosample).tap { it.update_column(:user_id, users(:carol).id) }

    post submission_messages_path(other),
         params:  {submission_message: {body: 'hijack'}}.to_json,
         headers: {'Content-Type' => 'application/json'}

    assert_response :not_found
  end
end
