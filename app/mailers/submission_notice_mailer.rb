# Tells a submitter of a notice DDBJ posted to their request's thread
# (SubmissionNotice): accessions issued, data made public, DRA reads
# checked. One mail per notice — for BS the numbers are listed in it
# rather than mailed per sample.
#
# The mail is the notice's notification and says what the notice says:
# the thread is where it is kept and where the submitter answers it,
# since nothing reads replies to this mail. So every action renders the
# same template, and differs only in its subject.
#
# Delivered via `MailDeliveryJob` (configured at application level), so
# transient mail1i timeouts retry on a polynomial backoff before
# failing the SolidQueue job.
class SubmissionNoticeMailer < ApplicationMailer
  # `first` and `count` rather than the list: the job row carries its
  # arguments, and the list can run to a hundred thousand.
  def accession_issued
    notify "#{'accession'.pluralize(params[:count])} issued", listed
  end

  def published
    notify 'made public', listed
  end

  # Before it is applied a submission has no number, only its request's.
  def reads_checked
    notify 'reads checked', "##{params[:notice].submission_request_id}"
  end

  private

  def notify(what, about)
    @notice  = params[:notice]
    @request = @notice.submission_request

    to = recipient_for(@request.user) or return

    mail(to:, subject: "[DDBJ Repository] #{Submission.db_label(@request.db)} #{what}: #{about}", template_name: 'notice')
  end

  def listed
    more = " (+#{(params[:count] - 1).to_fs(:delimited)} more)" if params[:count] > 1

    "#{params[:first]}#{more}"
  end
end
