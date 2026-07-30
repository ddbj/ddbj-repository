require 'test_helper'

class SubmissionMessageMailerTest < ActionMailer::TestCase
  setup do
    @request   = submission_requests(:bioproject)
    @curator   = users(:bob)
    @submitter = @request.user
  end

  test 'notify_submitter goes to the request owner with curator uid in body' do
    message = @request.messages.create!(user: @curator, author_role: :curator, body: 'Please add organism details.')
    mail    = SubmissionMessageMailer.with(message:).notify_submitter

    assert_equal ['alice@example.com'],           mail.to
    assert_match(/##{@request.id}/,               mail.subject)
    assert_match @curator.uid,                    mail.text_part.body.to_s
    assert_match 'Please add organism details.',  mail.text_part.body.to_s
  end

  test 'notify_curators recipients are deduplicated unique curators who have posted' do
    @request.messages.create!(user: users(:bob), author_role: :curator, body: 'A')
    @request.messages.create!(user: users(:bob), author_role: :curator, body: 'B') # same curator
    submitter_msg = @request.messages.create!(user: @submitter, author_role: :submitter, body: 'reply')

    mail = SubmissionMessageMailer.with(message: submitter_msg).notify_curators

    assert_equal ['bob@example.com'], mail.to
  end

  test 'notify_curators drops a curator with no known address' do
    users(:bob).update!(email: nil)

    @request.messages.create!(user: users(:bob), author_role: :curator, body: 'A')
    submitter_msg = @request.messages.create!(user: @submitter, author_role: :submitter, body: 'reply')

    mail = SubmissionMessageMailer.with(message: submitter_msg).notify_curators

    assert_empty mail.to.to_a
  end

  test 'notify_submitter sends nothing when the submitter address is unknown' do
    @submitter.update!(email: nil)

    message = @request.messages.create!(user: @curator, author_role: :curator, body: 'anyone there?')
    mail    = SubmissionMessageMailer.with(message:).notify_submitter

    assert_empty mail.to.to_a
  end

  test 'notify_curators is a no-op (no recipients) when no curator has posted yet' do
    msg  = @request.messages.create!(user: @submitter, author_role: :submitter, body: 'unprompted')
    mail = SubmissionMessageMailer.with(message: msg).notify_curators

    # Rails returns an empty Mail object when the action calls no mail()
    # — deliver_later is a no-op for it, but assert the To is empty.
    assert_empty mail.to.to_a
  end
end
