# Drawing one accessioned row's record.
#
# Two screens do this: the submitter's own, and a review link's. They
# differ in how the row is found — one by the submission it belongs to,
# the other by what the link carries — and in nothing after that. What
# the read costs, what invalidates it and what bounds the layout are the
# same question on both, and are exactly the kind of thing that drifts
# apart while both screens go on looking right.
module AccessionRecordReadable
  extend ActiveSupport::Concern

  # How much of a collection these screens draw before they stop. Not
  # RecordOutline's own limit, which is for a whole record: there the
  # collection being cut is `samples`, which has a screen of its own.
  # Here it is one row's — a sample's attribute bag — and there is no
  # other screen for it.
  #
  # Measured 2026-09-04 over D-way's 2,000,619 BioSamples: median 15
  # attributes, p95 19, p99 23, maximum 109. At 20 the cut fell just
  # above p95 and took 50,578 samples with it. 200 is the round number
  # above that maximum — headroom rather than a derived value, so it
  # bounds a record that is pathological rather than merely large.
  # NODE_BUDGET is the backstop either way.
  INLINE_LIMIT = 200

  private

  # What a reader's copy of this row would be stale against.
  #
  # The head of the chain, not the cache stamp. Asking before the read is
  # the point of asking, and at that moment the stamp is nil for the
  # first read after every edit — so two different states would answer
  # with the same etag and the second read would be a 304 over the first
  # read's body. The head is one indexed query, monotonic, and says
  # nothing about whether anything is cached.
  #
  # ST.26 has no chain: its record is the attachment, so the blob's
  # identity is its version.
  def record_etag(submission, row)
    [submission.updates.maximum(:id), submission.ddbj_record_attachment&.blob_id, row.accession, row.updated_at]
  end

  # The row's own subtree, laid out.
  #
  # The whole of it, not a chosen subset: RecordOutline names no field,
  # which is what lets it show a v3 key the day it appears instead of the
  # day somebody revises a renderer. What bounds it is the subtree — a
  # sample is a sample's fields, and the submitters beside it in the
  # record are not part of one.
  def record_outline(submission, row)
    slice = submission.record_slice(row)

    [slice, RecordOutline.new(slice.subtree, inline_limit: INLINE_LIMIT)]
  end
end
