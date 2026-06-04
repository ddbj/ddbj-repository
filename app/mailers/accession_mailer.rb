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

    mail(
      to:      submitter_email_or_uid(@submission),
      subject: subject_line(@submission, @accessions)
    )
  end

  private

  # Falls back to a uid placeholder when Cloakman lookup is not available
  # (dev without cloakman setup; see [[project-dev-cloakman-setup]]).
  # Production / staging will resolve to the real email via the
  # admin/users CloakmanClient lookup once the integration is set up.
  def submitter_email_or_uid(submission)
    submission.user.try(:email).presence || "#{submission.user.uid}@placeholder.invalid"
  end

  def subject_line(submission, accessions)
    db    = submission.db.humanize
    first = accessions.first
    rest  = accessions.size - 1

    return "[DDBJ Repository] #{db} accession issued" if first.nil?
    return "[DDBJ Repository] #{db} accession issued: #{first}" if rest.zero?

    "[DDBJ Repository] #{db} accessions issued: #{first} (+#{rest} more)"
  end
end
