# A submission's own accessions, whichever of the three databases it is.
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
  include EnumFilterable

  # Readable, not owned. The submission's own screen opens for a set's
  # members, and the accessions are a large part of why somebody looks at
  # a colleague's submission at all.
  def index
    submission = Submission.readable_by(current_user).find(params.expect(:submission_id))
    scope      = submission.accessioned_rows

    scope = filter_by_status(scope, params[:status]) if params[:status].present?

    # By id, which is the order they were submitted in — the order the
    # reader has in the file they are checking this against. Not by
    # accession: ST.26 draws nucleotide and amino-acid numbers from two
    # sequences with disjoint prefixes, so sorting on the number would
    # split a submission into two blocks that appear nowhere in its XML.
    @rows = paginate(scope.order(:id))
  end

  private

  # Refused rather than dropped. Intersecting an unknown value away would
  # answer "which of these are withdrawn" with every row there is, and a
  # client cannot tell that from a real answer — the same reasoning the
  # flat walk applies to the same parameter.
  def filter_by_status(scope, raw)
    filter_by_enum(scope, :status, raw, scope.model.statuses.keys)
  end
end
