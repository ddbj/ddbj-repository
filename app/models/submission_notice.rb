# What DDBJ tells a submitter of its own accord, posted to the request's
# thread as a `system` message. The thread is where everything said about
# a request is kept, so a notice the submitter was mailed is one they can
# find again — and answer — beside the conversation it belongs to. The
# mail that goes with it is its notification, and carries the same text.
module SubmissionNotice
  # A notice is read in a thread and in a mail, and neither is the place
  # for a hundred thousand sample accessions. Past this many the list
  # gives way to where the rest can be read.
  LIST_LIMIT = 100

  module_function

  # `names` is what each accession is the submitter's name for, where
  # there is one.
  def accession_issued!(submission, accessions, names: {})
    request = submission.request

    lines = accessions.first(LIST_LIMIT).map { ["  - #{it}", names[it]].compact.join('  ') }
    rest  = accessions.size - LIST_LIMIT

    lines << "  …and #{rest.to_fs(:delimited)} more #{rest_of(request)}" if rest.positive?

    post! request, <<~BODY.chomp
      We have issued #{accessions.size.to_fs(:delimited)} #{'accession'.pluralize(accessions.size)} for your #{Submission.db_label(submission.db)} submission (#{submission.source_id.presence || "##{request.id}"}).

      #{lines.join("\n")}
    BODY
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

  def post!(request, body)
    request.messages.create!(author_role: :system, body:)
  end
end
