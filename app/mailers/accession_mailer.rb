# Notifies submitters that accessions have been issued for their
# submission. One mail per issuance — for BS we list the newly-issued
# SAMD accessions in a single mail rather than spamming the submitter per
# sample.
#
# The mail is the notification of a notice posted to the request's thread
# (SubmissionNotice), and says what the notice says: the thread is where
# it is kept and where the submitter answers it, since nothing reads
# replies to this mail.
#
# Delivered via `MailDeliveryJob` (configured at application level), so
# transient mail1i timeouts retry on a polynomial backoff before
# failing the SolidQueue job.
class AccessionMailer < ApplicationMailer
  def issued
    @notice  = params[:notice]
    @request = @notice.submission_request

    to = recipient_for(@request.user) or return

    mail(to:, subject: subject_line(params[:first], params[:count]))
  end

  private

  def subject_line(first, count)
    db = Submission.db_label(@request.db)

    return "[DDBJ Repository] #{db} accession issued: #{first}" if count == 1

    "[DDBJ Repository] #{db} accessions issued: #{first} (+#{(count - 1).to_fs(:delimited)} more)"
  end
end
