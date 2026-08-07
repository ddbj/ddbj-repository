class AccessionsController < ApplicationController
  include EnumFilterable

  SYNC_LIMIT = 1000

  def index
    scope = scoped_entries
    scope = filter_by_status(scope, params[:status]) if params[:status].present?

    pagy, @accessions = pagy(scope.order(:id), **pagination)

    response.headers.merge! pagy.headers_hash
  end

  def show
    @accession = owned_entries.find_by!(accession: params[:number])
  end

  private

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

  # From the path, not from `params`: a `?submission_id=` in the query
  # string would otherwise switch the flat endpoint to nested semantics —
  # scoping the list, dropping the page size to 20, and 404ing on an id
  # the caller does not own, none of which /accessions declares.
  def nested_submission_id = request.path_parameters[:submission_id]

  def scoped_entries
    return owned_entries unless nested_submission_id

    current_user.submissions.find(nested_submission_id).entries
  end

  def owned_entries
    Entry.joins(:submission).merge(current_user.submissions)
  end

  # A page of the nested list is read by a person, a page of the flat one
  # by a script keeping a local copy in step. Twenty rows at a time is
  # right for the first and is tens of thousands of requests for the
  # second when a whole submission has been retracted at once.
  def pagination
    nested_submission_id ? {} : {limit: SYNC_LIMIT}
  end

  def filter_by_status(scope, raw)
    filter_by_enum(scope, :status, raw, Entry.statuses.keys)
  end
end
