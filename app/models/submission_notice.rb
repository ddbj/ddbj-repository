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
    request = submission.request

    post! request, "We have issued #{counted(accessions)} for your #{described(request)}.", listed(accessions, names), rest_of(request)
  end

  # Mailed once the change is committed: a notice rolled back with the
  # status it announced must not have been mailed already. And only
  # attempted — the notice in the thread is the record, and a queue that
  # is down must not turn a publication already committed into an error.
  def published!(submission, accessions, names: {})
    request = submission.request
    notice  = post!(request, "#{what_is_public(submission, accessions.size)} now public.", listed(accessions, names), rest_of(request))

    mail_once_committed(:published, notice:, first: accessions.first, count: accessions.size)

    notice
  end

  # A DRA check held for its reads (DDBJValidatorCheck.hold), concluded:
  # hours after it was started, with nobody watching the screen. Its
  # findings — the validator's on the metadata and those on the reads —
  # are written out rather than pointed at, because checking again
  # replaces them and the thread is where "what is wrong with these?" is
  # asked. Mailed once committed, as above.
  #
  # The subject is a request: only a request is checked by ddbj-validator
  # (ValidateDDBJRecordJob), and only a request has a thread.
  def reads_checked!(validation)
    request = validation.subject
    details = validation.details.order(:id).to_a
    rest    = "on the web: #{WebApp.url_for("/requests/#{request.id}")}"
    notice  = post!(request, reads_outcome(request, details), details.map { finding(it) }, rest)

    mail_once_committed(:reads_checked, notice:)

    notice
  end

  def post!(request, sentence, lines, rest_where)
    rest  = lines.size - LIST_LIMIT
    lines = lines.first(LIST_LIMIT)

    lines << "  …and #{rest.to_fs(:delimited)} more #{rest_where}" if rest.positive?

    request.messages.create!(author_role: :system, body: [sentence, lines.join("\n").presence].compact.join("\n\n"))
  end

  def mail_once_committed(action, **params)
    ActiveRecord.after_all_transactions_commit do
      SubmissionNoticeMailer.with(**params).public_send(action).deliver_later
    rescue StandardError => e
      Rails.error.report(e, handled: true, source: "submission_notice.#{action}")
    end
  end

  def listed(accessions, names) = accessions.map { ["  - #{it}", names[it]].compact.join('  ') }

  def counted(accessions) = "#{accessions.size.to_fs(:delimited)} #{'accession'.pluralize(accessions.size)}"

  # What was made public is the submission's projects or samples, not its
  # numbers — and all of it, where the submission is one row.
  def what_is_public(submission, count)
    return "Your #{described(submission.request)} is" if submission.single_row_db?

    "#{count.to_fs(:delimited)} #{submission.curation_row_noun.pluralize(count)} of your #{described(submission.request)} #{count == 1 ? 'is' : 'are'}"
  end

  def reads_outcome(request, details)
    errors   = details.count { it.error? && it.code != DDBJValidatorCheck::NOT_CHECKED }
    found    = "#{errors} #{'error'.pluralize(errors)}"
    fix      = 'Please correct the record or its files, and check it again:'
    sendable = "It can be sent to DDBJ on the web within #{Validation::FRESH_FOR.in_hours.to_i} hours; after that it has to be checked again."

    if details.any? { it.code == DDBJValidatorCheck::NOT_CHECKED }
      checked = "We could not finish checking your #{described(request)}"

      errors.zero? ? "#{checked}. Please check it again later:" : "#{checked}, and found #{found} in what was checked. #{fix}"
    else
      checked = "We have checked your #{described(request)}, its reads included"

      if errors.positive?
        "#{checked}, and found #{found}. #{fix}"
      elsif details.any?
        "#{checked}. #{sendable} These warnings were found:"
      else
        "#{checked}, and found nothing wrong. #{sendable}"
      end
    end
  end

  # One finding, as the request page shows it: what it is about, and what
  # is wrong. What the tools said runs to several lines, kept under it.
  def finding(detail)
    head, *rest = "#{detail.severity.capitalize}#{" (#{detail.entry_id})" if detail.entry_id}: #{detail.message}".lines(chomp: true)

    ["  - #{head}", *rest.map { "    #{it}" }].join("\n")
  end

  # By the name the submitter knows it by: D-way's, or the request's own.
  def described(request)
    "#{Submission.db_label(request.db)} submission (#{request.submission&.source_id.presence || "##{request.id}"})"
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

  private_class_method :post!, :mail_once_committed, :listed, :counted, :what_is_public, :reads_outcome, :finding, :described, :rest_of
end
