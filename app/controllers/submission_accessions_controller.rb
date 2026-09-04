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

  # How much of a collection this screen draws before it stops. Not
  # RecordOutline's own limit, which is for a whole record: there the
  # collection being cut is `samples`, which has a screen of its own. Here
  # it is one row's — a sample's attribute bag — and there is no other
  # screen for it.
  #
  # Measured 2026-09-04 over D-way's 2,000,619 BioSamples: median 15
  # attributes, p95 19, p99 23, maximum 109. At 20 the cut fell just
  # above p95 and took 50,578 samples with it. 200 is the round number
  # above that maximum — headroom rather than a derived value, so it
  # bounds a record that is pathological rather than merely large.
  # NODE_BUDGET is the backstop either way.
  INLINE_LIMIT = 200

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

  # What one accession's record says, laid out by the shape of the data.
  #
  # The whole of that record's own subtree, not a chosen subset:
  # RecordOutline names no field, which is what lets it show a v3 key the
  # day it appears instead of the day somebody revises a renderer. What
  # bounds it is the subtree — a sample is a sample's fields, and the
  # submitters beside it in the record are not part of one.
  def show
    submission = Submission.readable_by(current_user).find(params.expect(:submission_id))
    accession  = params.expect(:accession)

    @row = submission.accessioned_rows.find_by!(accession:)

    # Asked before the record is read, which is the whole point of asking:
    # a slice costs a blob download and a streamed parse, and a reader
    # who already has this version should pay for neither.
    #
    # The stamp is the version. Any edit to the chain nil-clears it
    # (SubmissionUpdate's in-transaction hooks), so an etag built from it
    # is one a change invalidates.
    #
    # Private: what it holds is one submitter's record, and a shared
    # cache is a place for it to be read by somebody the scope above
    # refused.
    # The head of the chain, not the cache stamp. Asking before the read
    # is the point of asking, and at that moment the stamp is nil for the
    # first read after every edit — so two different states would answer
    # with the same etag and the second read would be a 304 over the
    # first read's body. The head is one indexed query, monotonic, and
    # says nothing about whether anything is cached.
    #
    # ST.26 has no chain: its record is the attachment, so the blob's
    # identity is its version.
    version = [submission.updates.maximum(:id), submission.ddbj_record_attachment&.blob_id]

    return unless stale?(etag: [*version, accession, @row.updated_at], public: false)

    @slice   = submission.record_slice(@row)
    @outline = RecordOutline.new(@slice.subtree, inline_limit: INLINE_LIMIT)
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
