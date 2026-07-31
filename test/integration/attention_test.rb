require 'test_helper'

class AttentionTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"
  end

  test 'empty when nothing is waiting on the submitter' do
    get attention_path

    assert_conform_schema 200
    assert_empty response.parsed_body.fetch('requests')
  end

  test 'lists requests with an unread curator message' do
    waiting = submission_requests(:biosample)
    waiting.messages.create!(user: users(:bob), author_role: 'curator', body: 'a question')

    get attention_path

    assert_conform_schema 200

    requests = response.parsed_body.fetch('requests')

    assert_equal [waiting.id],        requests.pluck('id')
    assert_equal ['unread_message'],  requests.pluck('reason')
  end

  # Both are the submitter's move, and each is made somewhere else — one
  # on the request's Apply button, one in its thread. The band says which.
  test 'lists a validated file waiting to be applied, and one that failed validation' do
    ready  = submission_requests(:biosample)
    failed = submission_requests(:st26)

    ready.update_columns(status: SubmissionRequest.statuses.fetch('ready_to_apply'))
    failed.update_columns(status: SubmissionRequest.statuses.fetch('validation_failed'))

    get attention_path

    assert_conform_schema 200

    assert_equal({failed.id => 'validation_failed', ready.id => 'ready_to_apply'},
                 response.parsed_body.fetch('requests').to_h { [it.fetch('id'), it.fetch('reason')] })
  end

  # A failed Apply is DDBJ's to fix — see CurationQueue's :stuck bucket.
  # Telling the submitter to act on it only makes them resubmit a file
  # that was fine.
  test 'ignores a failed application' do
    submission_requests(:biosample).update_columns(status: SubmissionRequest.statuses.fetch('application_failed'))

    get attention_path

    assert_conform_schema 200
    assert_empty response.parsed_body.fetch('requests')
  end

  # The submitter's own reply is not something they need reminding about.
  test 'ignores the submitter own unread messages' do
    submission_requests(:biosample).messages.create!(user: @user, author_role: 'submitter', body: 'my reply')

    get attention_path

    assert_conform_schema 200
    assert_empty response.parsed_body.fetch('requests')
  end

  test 'a read message drops off the list' do
    request = submission_requests(:biosample)
    request.messages.create!(user: users(:bob), author_role: 'curator', body: 'a question', read_at: Time.current)

    get attention_path

    assert_conform_schema 200
    assert_empty response.parsed_body.fetch('requests')
  end

  test 'never leaks another user request' do
    other = SubmissionRequest.new(user: users(:carol), db: 'st26')
    attach_ddbj_record(other)
    other.save!
    other.messages.create!(user: users(:bob), author_role: 'curator', body: 'not yours')

    get attention_path

    assert_conform_schema 200
    assert_empty response.parsed_body.fetch('requests')
  end

  test 'requires authentication' do
    default_headers.delete('Authorization')

    get attention_path

    assert_conform_schema 401
  end
end
