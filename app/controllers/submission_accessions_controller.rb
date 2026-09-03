# A submission\'s own accessions, whichever of the three databases it is.
#
# This used to be the flat synchronisation endpoint under another path,
# and it read `entries` — so every BioProject and BioSample in the archive
# answered with an empty list and a count of zero, for numbers that were
# plainly there on the screen it was reached from.
#
# The shape follows: an accession, what the record calls itself, and what
# else that record states as labelled facts, because the three databases
# agree on the first two and on nothing after them.
class SubmissionAccessionsController < ApplicationController
  # Readable, not owned. The submission\'s own screen opens for a set\'s
  # members, and the accessions are a large part of why somebody looks at
  # a colleague\'s submission at all.
  def index
    submission = Submission.readable_by(current_user).find(params.expect(:submission_id))

    @rows = paginate(submission.accessioned_rows.order(:accession))
  end
end
