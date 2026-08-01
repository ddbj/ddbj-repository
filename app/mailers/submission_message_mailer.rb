# Notifies the other side of the conversation when a SubmissionMessage
# is posted. Reply is always done via the web UI (per the design
# decision logged in [[project-submission-messaging-design]]), so these
# mails are notification-only — there is no inbound mail ingestion.
class SubmissionMessageMailer < ApplicationMailer
  # Curator → submitter. The body shows the curator's name so the
  # submitter knows who's asking; the From header stays as the shared
  # `DDBJ Repository <repo@…>` (decision 3-iii) so a curator handover
  # doesn't leave the submitter replying to a stale personal mailbox.
  def notify_submitter
    @message = params[:message]
    @request = @message.submission_request
    @curator = @message.user

    to = recipient_for(@request.user) or return

    mail(to:, subject: "[DDBJ Repository] New curator message on ##{@request.id}")
  end

  # Submitter → curators. Notifies every curator who has previously
  # posted in this thread (the natural set of "involved" curators —
  # avoids spamming the whole admin pool on every reply). Each curator gets
  # the mail at their own address; curators we have no address for are
  # dropped, and a thread where nobody is reachable sends nothing.
  def notify_curators
    @message = params[:message]
    @request = @message.submission_request

    recipients = involved_curator_emails
    return if recipients.empty?

    mail(
      to:      recipients,
      subject: "[DDBJ Repository] Submitter replied on ##{@request.id}"
    )
  end

  # Copied in by a colleague. A separate mail from the submitter's,
  # because the audience and the ask are different: the submitter is
  # being answered, these curators are being shown something.
  #
  # It has to be a mail rather than only a subscription. A curator who
  # has just replied leaves nothing unanswered, so the queue would say
  # nothing about the request until the submitter writes back — which
  # may be never, and is not when they were asked to look.
  def copied_in
    @message = params[:message]
    @request = @message.submission_request

    recipients = @message.cc_users.filter_map { recipient_for(it) }
    return if recipients.empty?

    mail(
      to:      recipients,
      subject: "[DDBJ Repository] #{@message.user.uid} copied you in on ##{@request.id}"
    )
  end

  private

  def involved_curator_emails
    # `distinct.pluck` collapses N curator messages from the same user
    # into one user_id at the DB level so we don't load (and dedupe in
    # Ruby) 50 copies of Alice just because she posted 50 messages.
    # `reorder(nil)` strips the chronological scope's ORDER BY —
    # Postgres requires DISTINCT columns to appear in ORDER BY.
    user_ids = @request.messages.curator_role.reorder(nil).distinct.pluck(:user_id)

    # Minus anyone who has stopped following. Silencing the queue but not
    # the mail would leave the escape hatch doing almost nothing: the
    # curator who asked to be left out of a thread would go on being told
    # about every reply to it.
    user_ids -= @request.participations.where.not(unsubscribed_at: nil).pluck(:user_id)

    User.where(id: user_ids).filter_map { recipient_for(it) }
  end
end
