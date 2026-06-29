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
    @message    = params[:message]
    @submission = @message.submission
    @curator    = @message.user

    mail(
      to:      user_email_or_placeholder(@submission.user),
      subject: "[DDBJ Repository] New curator message on Submission-#{@submission.id}"
    )
  end

  # Submitter → curators. Notifies every curator who has previously
  # posted in this thread (the natural set of "involved" curators —
  # avoids spamming the whole admin pool on every reply). Each curator
  # gets the mail at their own address looked up via the same
  # placeholder fallback the submitter side uses.
  def notify_curators
    @message    = params[:message]
    @submission = @message.submission

    recipients = involved_curator_emails
    return if recipients.empty?

    mail(
      to:      recipients,
      subject: "[DDBJ Repository] Submitter replied on Submission-#{@submission.id}"
    )
  end

  private

  def involved_curator_emails
    # `distinct.pluck` collapses N curator messages from the same user
    # into one user_id at the DB level so we don't load (and dedupe in
    # Ruby) 50 copies of Alice just because she posted 50 messages.
    # `reorder(nil)` strips the chronological scope's ORDER BY —
    # Postgres requires DISTINCT columns to appear in ORDER BY.
    user_ids = @submission.messages.curator_role.reorder(nil).distinct.pluck(:user_id)
    User.where(id: user_ids).map { user_email_or_placeholder(it) }
  end
end
