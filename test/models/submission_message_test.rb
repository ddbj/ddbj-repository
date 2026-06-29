require 'test_helper'

class SubmissionMessageTest < ActiveSupport::TestCase
  setup do
    @submission = submissions(:bioproject)
  end

  test 'rejects unknown author_role' do
    msg = @submission.messages.build(user: users(:bob), author_role: 'system', body: 'x')

    assert_not msg.valid?
    assert_includes msg.errors[:author_role], 'is not included in the list'
  end

  test 'requires a body' do
    msg = @submission.messages.build(user: users(:bob), author_role: 'curator', body: '')

    assert_not msg.valid?
    assert_includes msg.errors[:body], "can't be blank"
  end

  test 'chronological scope orders by created_at then id' do
    older = @submission.messages.create!(user: users(:bob), author_role: :curator, body: 'first')
    newer = @submission.messages.create!(user: users(:alice), author_role: :submitter, body: 'second')

    assert_equal [older, newer], @submission.messages.chronological.to_a
  end

  test 'unread scope returns only rows with read_at NULL' do
    unread = @submission.messages.create!(user: users(:bob), author_role: :curator, body: 'pending')
    @submission.messages.create!(user: users(:alice), author_role: :submitter, body: 'seen', read_at: Time.current)

    assert_equal [unread], @submission.messages.unread.to_a
  end
end
