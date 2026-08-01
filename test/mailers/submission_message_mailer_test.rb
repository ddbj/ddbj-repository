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

  # Everyone following it, once each — posting is one of the ways to
  # start following, not the definition of who is told.
  test 'notify_curators recipients are the unique curators following it' do
    @request.subscribe!(users(:bob))
    @request.messages.create!(user: users(:bob), author_role: :curator, body: 'A')
    @request.messages.create!(user: users(:bob), author_role: :curator, body: 'B') # same curator
    submitter_msg = @request.messages.create!(user: @submitter, author_role: :submitter, body: 'reply')

    mail = SubmissionMessageMailer.with(message: submitter_msg).notify_curators

    assert_equal ['bob@example.com'], mail.to
  end

  test 'notify_curators drops a curator with no known address' do
    users(:bob).update!(email: nil)

    @request.subscribe!(users(:bob))
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

  # Silencing the queue but not the mail would leave the escape hatch
  # doing almost nothing: the curator who asked to be left out of a
  # thread would go on being told about every reply to it.
  test 'a curator who stopped following is not mailed about replies' do
    request = submission_requests(:bioproject)
    request.subscribe!(users(:bob))
    request.subscribe!(users(:dave))
    reply = request.messages.create!(user: users(:alice), author_role: :submitter, body: 'answered')

    request.unsubscribe!(users(:bob))

    mail = SubmissionMessageMailer.with(message: reply).notify_curators

    assert_not_includes Array(mail.to), users(:bob).email
    assert_includes     Array(mail.to), users(:dave).email
  end

  # Copied in without having posted. They are subscribed, so the request
  # reaches their queue — and the mail that copied them in says replies
  # will too, which was not true while the recipient list was built from
  # who had posted.
  test 'a curator copied in is mailed the reply, though they never posted' do
    @request.subscribe!(users(:dave))
    reply = @request.messages.create!(user: @submitter, author_role: :submitter, body: 'answered')

    mail = SubmissionMessageMailer.with(message: reply).notify_curators

    assert_includes Array(mail.to), users(:dave).email
    assert_empty @request.messages.curator_role, 'they never posted'
  end

  # Body is optional now, so an attachment-only message would otherwise
  # arrive as a heading followed by nothing at all — no quote, no mention
  # that anything is attached.
  test 'an attachment-only message names the file it is about' do
    message = @request.messages.new(user: @curator, author_role: :curator, body: '')
    message.files.attach(io: StringIO.new('x'), filename: 'samples.tsv', content_type: 'text/plain')
    message.save!

    mail = SubmissionMessageMailer.with(message:).notify_submitter

    assert_match 'samples.tsv', mail.text_part.body.to_s
    assert_match 'samples.tsv', mail.html_part.body.to_s
  end
end
