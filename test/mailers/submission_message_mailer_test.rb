require 'test_helper'

class SubmissionMessageMailerTest < ActionMailer::TestCase
  setup do
    @submission = submissions(:bioproject)
    @curator    = users(:bob)
    @submitter  = @submission.user
  end

  test 'notify_submitter goes to the submission owner with curator uid in body' do
    message = @submission.messages.create!(user: @curator, author_role: :curator, body: 'Please add organism details.')
    mail    = SubmissionMessageMailer.with(message:).notify_submitter

    # Placeholder fallback when no Cloakman lookup is wired — same shape
    # AccessionMailer falls back to in dev. Real prod resolves via
    # Cloakman once integration lands.
    assert_equal ["#{@submitter.uid}@placeholder.invalid"], mail.to
    assert_match(/Submission-#{@submission.id}/,           mail.subject)
    assert_match @curator.uid,                             mail.text_part.body.to_s
    assert_match 'Please add organism details.',           mail.text_part.body.to_s
  end

  test 'notify_curators recipients are deduplicated unique curators who have posted' do
    @submission.messages.create!(user: users(:bob), author_role: :curator, body: 'A')
    @submission.messages.create!(user: users(:bob), author_role: :curator, body: 'B') # same curator
    submitter_msg = @submission.messages.create!(user: @submitter, author_role: :submitter, body: 'reply')

    mail = SubmissionMessageMailer.with(message: submitter_msg).notify_curators

    assert_equal ["#{users(:bob).uid}@placeholder.invalid"], mail.to
  end

  test 'notify_curators is a no-op (no recipients) when no curator has posted yet' do
    msg  = @submission.messages.create!(user: @submitter, author_role: :submitter, body: 'unprompted')
    mail = SubmissionMessageMailer.with(message: msg).notify_curators

    # Rails returns an empty Mail object when the action calls no mail()
    # — deliver_later is a no-op for it, but assert the To is empty.
    assert_empty mail.to.to_a
  end
end
