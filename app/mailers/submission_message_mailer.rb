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

  # Something happened on a request you follow. Curator-authored
  # messages used to reach nobody but the submitter, so a curator
  # following a request learned nothing when a colleague answered on it —
  # and since answering settles the thread, it left their queue at the
  # same moment, making that the one event they could never find out
  # about.
  #
  # Excludes the author, and anyone being copied in on this very message:
  # they get the more direct `copied_in` instead.
  def followed_activity
    @message = params[:message]
    @request = @message.submission_request

    recipients = @request.followers_to_notify(@message).filter_map { recipient_for(it) }
    return if recipients.empty?

    mail(
      to:      recipients,
      subject: "[DDBJ Repository] #{@message.user.uid} replied to the submitter on ##{@request.id}"
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

  # Everyone following it, which is now a thing the request can say
  # directly. It used to be everyone who had POSTED, minus anyone who had
  # unsubscribed — which is nearly the same set and quietly missed one:
  # a curator copied in on a thread is subscribed without having posted,
  # so they were told once and then never again, while the mail that
  # copied them in promised the opposite.
  def involved_curator_emails
    @request.followers.filter_map { recipient_for(it) }
  end
end
