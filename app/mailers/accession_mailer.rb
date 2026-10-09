# Notifies submitters that an accession has been issued for their BP /
# BS submission. One mail per submission — for BS we attach the list of
# newly-issued SAMD accessions to a single mail rather than spamming
# the submitter per sample.
#
# Delivered via `MailDeliveryJob` (configured at application level), so
# transient mail1i timeouts retry on a polynomial backoff before
# failing the SolidQueue job.
class AccessionMailer < ApplicationMailer
  def issued
    @submission = params[:submission]
    @accessions = Array(params[:accessions]).compact

    # What each is the submitter's name for, where there is one: a DRA
    # submission's numbers are its runs', experiments' and analyses', and a
    # list of thousands of DRR does not say which is whose.
    @names = params[:names] || {}

    to = recipient_for(@submission.user) or return

    mail(to:, subject: subject_line(@submission, @accessions))
  end

  private

  def subject_line(submission, accessions)
    db    = Submission.db_label(submission.db)
    first = accessions.first
    rest  = accessions.size - 1

    return "[DDBJ Repository] #{db} accession issued" if first.nil?
    return "[DDBJ Repository] #{db} accession issued: #{first}" if rest.zero?

    "[DDBJ Repository] #{db} accessions issued: #{first} (+#{rest} more)"
  end
end
