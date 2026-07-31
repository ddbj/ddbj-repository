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
    assert_equal [waiting.id], response.parsed_body.fetch('requests').pluck('id')
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
