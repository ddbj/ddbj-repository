class ReviewsController < ApplicationController
  include AccessionRecordReadable

  # The whole point is unauthenticated access via the share token.
  skip_before_action :authenticate!, only: %i[show accessions accession]

  before_action :load_access

  # An invalid OR expired token 404s (via find_by! on the `active` scope),
  # so a reviewer can't tell a revoked link from one that never existed.
  #
  # What is answered here is the link, not what is on it: the set's name
  # and when it stops working. The accessions are their own route because
  # there is no bound on how many there are.
  def show; end

  # What was shared, a page at a time, and never the submissions the
  # accessions came from. That is the change of granularity: at accession
  # granularity there is no file to hand over — a record or a flatfile is
  # the whole submission, and the whole submission is the thing that was
  # deliberately not shared — so what a reviewer gets is what these
  # accessions say, drawn on the page.
  #
  # A page can come back shorter than it was asked for. The rows are
  # resolved through the set (ReviewerAccess#shared_rows), so an accession
  # whose submission has left the set is not on it any more even though
  # its row is still named — the tidying that follows a removal is what
  # closes the gap, and this is what holds until it has.
  def accessions
    @rows = @access.shared_rows(paginate(@access.shared_accessions).map(&:accession))
  end

  # What one of those accessions says, laid out by the shape of the data —
  # the same layout the submitter's own screen draws.
  #
  # This is the door the granularity left open. A record and a flatfile
  # are the whole submission, so neither can be handed over; the row's own
  # subtree is exactly what was shared, and reading it needs no file to
  # leave the building.
  #
  # 404 for an accession this link does not carry, whether it is in the
  # set, in another set, or nowhere — the same silence the token itself
  # keeps, and for the same reason.
  def accession
    @row = @access.shared_row(params.expect(:accession)) or raise ActiveRecord::RecordNotFound

    submission = @row.submission

    # Asked before the record is read, which is the whole point of asking:
    # a slice costs a blob download and a streamed parse, and a reader who
    # already has this version should pay for neither.
    #
    # Private, though the token is the credential: what it holds is one
    # submitter's record, and a shared cache is a place for it to be read
    # by somebody who never had the link.
    return unless stale?(etag: record_etag(submission, @row), public: false)

    @slice, @outline = record_outline(submission, @row)
  end

  private

  def load_access
    @access = ReviewerAccess.active.find_by!(token: params.expect(:token))
  end
end
