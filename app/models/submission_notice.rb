# What DDBJ tells a submitter of its own accord, posted to the request's
# thread as a `system` message. The thread is where everything said about
# a request is kept, so a notice the submitter was mailed is one they can
# find again — and answer — beside the conversation it belongs to. The
# mail that goes with it (SubmissionNoticeMailer) is its notification,
# and carries the same text.
module SubmissionNotice
  # A notice is read in a thread and in a mail, and neither is the place
  # for a hundred thousand sample accessions. Past this many the list
  # gives way to where the rest can be read.
  LIST_LIMIT = 100

  module_function

  # `names` is what each accession is the submitter's name for, where
  # there is one. Mailed by the caller, which knows whether the mail went
  # (AccessionIssuance#mail_status).
  def accession_issued!(submission, accessions, names: {})
    post! submission, "We have issued #{counted(accessions)} for your #{described(submission)}.", accessions, names
  end

  # Mailed once the change is committed: a notice rolled back with the
  # status it announced must not have been mailed already. And only
  # attempted — the notice in the thread is the record, and a queue that
  # is down must not turn a publication already committed into an error.
  def published!(submission, accessions, names: {})
    notice = post!(submission, "#{what_is_public(submission, accessions.size)} now public.", accessions, names)

    ActiveRecord.after_all_transactions_commit do
      SubmissionNoticeMailer.with(notice:, first: accessions.first, count: accessions.size).published.deliver_later
    rescue StandardError => e
      Rails.error.report(e, handled: true, source: 'submission_notice.published')
    end

    notice
  end

  def post!(submission, sentence, accessions, names)
    request = submission.request

    lines = accessions.first(LIST_LIMIT).map { ["  - #{it}", names[it]].compact.join('  ') }
    rest  = accessions.size - LIST_LIMIT

    lines << "  …and #{rest.to_fs(:delimited)} more #{rest_of(request)}" if rest.positive?

    request.messages.create!(author_role: :system, body: "#{sentence}\n\n#{lines.join("\n")}")
  end

  def counted(accessions) = "#{accessions.size.to_fs(:delimited)} #{'accession'.pluralize(accessions.size)}"

  # What was made public is the submission's projects or samples, not its
  # numbers — and all of it, where the submission is one row.
  def what_is_public(submission, count)
    return "Your #{described(submission)} is" if submission.single_row_db?

    "#{count.to_fs(:delimited)} #{submission.curation_row_noun.pluralize(count)} of your #{described(submission)} #{count == 1 ? 'is' : 'are'}"
  end

  # By the name the submitter knows it by: D-way's, or the request's own.
  def described(submission)
    "#{Submission.db_label(submission.db)} submission (#{submission.source_id.presence || "##{submission.request.id}"})"
  end

  # The accessions page lists curation rows, and a DRA submission is one
  # row: its experiments', runs' and analyses' numbers are in its record,
  # which the request page offers.
  def rest_of(request)
    if request.dra_db?
      "in the record: #{WebApp.url_for("/requests/#{request.id}")}"
    else
      "on the accessions page: #{WebApp.url_for("/requests/#{request.id}/accessions")}"
    end
  end

  private_class_method :post!, :counted, :what_is_public, :described, :rest_of
end
