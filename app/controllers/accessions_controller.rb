class AccessionsController < ApplicationController
  include EnumFilterable

  SYNC_LIMIT = 1000

  def index
    scope = scoped_entries
    scope = filter_by_status(scope, params[:status]) if params[:status].present?
    scope = scope.order(:id)

    return offset_page(scope) if nested_submission_id

    keyset_page(scope)
  end

  # Readable, like the list it is reached from. `owned_entries` below is
  # the flat synchronisation walk and stays "mine".
  def show
    @accession = readable_entries.find_by!(accession: params[:number])
  end

  private

  # From the path, not from `params`: a `?submission_id=` in the query
  # string would otherwise switch the flat endpoint to nested semantics —
  # scoping the list, dropping the page size to 20, and 404ing on an id
  # the caller does not own, none of which /accessions declares.
  def nested_submission_id = request.path_parameters[:submission_id]

  # Nested under a submission it is that submission's entries; on its own
  # it is every entry the caller has.
  #
  # The flat form is what makes "which of mine are no longer part of their
  # submission" one walk instead of one per submission. The bulk ST.26
  # client keeps a local copy of every entry it ever registered — millions
  # of rows across 143K submissions — and rebuilds its live list from it,
  # so it has to hear about a retraction it did not make. Asking that
  # submission by submission is hundreds of thousands of requests for an
  # answer that is usually a handful of rows.
  def scoped_entries
    return owned_entries unless nested_submission_id

    # Readable, not owned. The nested list is what the submission's own
    # screen shows, and that screen now opens for a set's members — the
    # accessions are a large part of why somebody looks at a colleague's
    # submission at all. The flat list below stays "mine": it is a
    # synchronisation walk, and widening it would put other people's rows
    # into a local copy that is meant to be one submitter's.
    Submission.readable_by(current_user).find(nested_submission_id).entries
  end

  def owned_entries
    Entry.joins(:submission).merge(current_user.submissions)
  end

  def readable_entries
    Entry.joins(:submission).merge(Submission.readable_by(current_user))
  end

  # A page of the nested list is read by a person: they want to know how
  # many there are and to jump about, so it is numbered and counted.
  def offset_page(scope)
    @accessions = paginate(scope)
  end

  # A page of the flat list is read by a script walking the whole set to
  # keep a local copy in step, and offset pagination is wrong for that
  # rather than merely slow: a row that disappears from a page already
  # read pulls every later row back one place, so the row on the far side
  # of the boundary is stepped over — the one thing a sync must not do.
  # Destroying a submission takes all of its entries at once, which is
  # that hazard several thousand times over.
  #
  # Inserts are not the hazard: ids ascend, so a new row lands after the
  # cursor and cannot disturb what came before it. Seeking past the last
  # id read is immune to both regardless.
  #
  # It also drops a COUNT over millions of rows per request and a
  # progressively larger OFFSET.
  #
  # `page` carries an opaque cursor rather than a number. `Next-Page` is
  # absent on the last page, which is how a client knows to stop —
  # there is no total to count down to.
  def keyset_page(scope)
    # A cursor the server cannot read is refused rather than treated as
    # "start again". Pagy decodes a bad one to nil and hands back page
    # one, which a walk reads as its own first page — the same reasoning
    # EnumFilterable applies to `status` two lines up, on the endpoint
    # whose whole purpose is a walk that does not lose its place.
    if params[:page].present? && Pagy::Keyset.decode(params[:page]).nil?
      raise EnumFilterable::UnknownFilterValue,
            'Unreadable page cursor. Pass back the Next-Page header of the previous response, or omit it to start.'
    end

    pagy = Pagy::Keyset.new(scope, limit: SYNC_LIMIT, page: params[:page])

    @accessions = pagy.records

    response.headers['Next-Page'] = pagy.next if pagy.next
  end

  def filter_by_status(scope, raw)
    filter_by_enum(scope, :status, raw, Entry.statuses.keys)
  end
end
