# Tells a submitter of a notice DDBJ posted to their request's thread
# (SubmissionNotice): accessions issued, data made public. One mail per
# notice — for BS the numbers are listed in it rather than mailed per
# sample.
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
    notify "#{'accession'.pluralize(params[:count])} issued"
  end

  def published
    notify 'made public'
  end

  private

  def notify(what)
    @notice  = params[:notice]
    @request = @notice.submission_request

    to = recipient_for(@request.user) or return

    mail(to:, subject: subject_line(what, params[:first], params[:count]), template_name: 'notice')
  end

  def subject_line(what, first, count)
    db   = Submission.db_label(@request.db)
    more = " (+#{(count - 1).to_fs(:delimited)} more)" if count > 1

    "[DDBJ Repository] #{db} #{what}: #{first}#{more}"
  end
end
