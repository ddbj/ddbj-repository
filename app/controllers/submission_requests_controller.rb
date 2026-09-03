class SubmissionRequestsController < ApplicationController
  include SourceIdFilterable
  include AccessionFilterable
  include AccessionSummaries
  include EnumFilterable

  # The submitter's list, organised around "where is this now".
  #
  # Submissions that are finished never stop taking up room — a lab with
  # 500 released records cannot see the three that are still moving — so
  # `phase` splits the live ones from the done ones and the counts for
  # both ride along in headers.
  #
  # Newest first, and only that unless asked otherwise. Floating the
  # requests that need the submitter is what their own screen wants, and
  # it has to happen across the whole list rather than within a page, so
  # it is a SQL predicate — but it makes the leading sort key something
  # that changes when the data does. A client walking the pages then has
  # rows move between them underneath it, and one old request floating
  # to the front is enough to make page 1 not look like the start of
  # anything. `needs_action_first` is how the screen asks for it.
  def index
    owned = current_user.submission_requests

    scope = owned.includes(submission: :project)
    scope = filter_by_phase(scope, params[:phase])
    scope = filter_by_db(scope, params[:db])               if params[:db].present?
    scope = filter_by_status(scope, params[:status])       if params[:status].present?
    scope = filter_by_source_id(scope, params[:source_id]) if params[:source_id].present?
    scope = filter_by_accession(scope, params[:accession]) if params[:accession].present?
    scope = scope.needs_submitter_action                   if params[:needs_action].present?

    @requests = paginate(order(scope))

    # Per-page BS accession aggregate ([first, count] keyed by submission
    # id) so the summary's DB-aware accession column doesn't N+1.
    @bs_accession_summaries = sample_accession_summaries(@requests.filter_map(&:submission))

    # "Where it is now" is derived from the curation rows behind each
    # request, which is three aggregate queries per row asked one at a
    # time — CurationState.batch asks once for the page.
    @states = CurationState.batch(@requests)

    # Pre-fetch the per-request unread curator message counts so the
    # summary doesn't N+1. One indexed query per page.
    @unread_counts =
      SubmissionMessage
        .curator_role.unread
        .where(submission_request_id: @requests.map(&:id))
        .group(:submission_request_id)
        .count

    response.headers['Unfinished-Count'] = owned.unfinished.count.to_s
    response.headers['Finished-Count']   = owned.finished.count.to_s
  end

  # Wider than the list above, which is "mine". A set's members can read
  # each other's submissions, and this is where they do it — the payload
  # says which of the two the reader is (`owned`), and withholds the
  # conversation either way.
  def show
    @request = SubmissionRequest.readable_by(current_user).find(params.expect(:id))
  end

  def create
    @request = current_user.submission_requests.create!(**request_params)

    raise ActiveRecord::RecordInvalid unless @request.waiting_validation?

    ValidateDDBJRecordJob.perform_later @request

    render :show, status: :accepted
  end

  private

  # Total and stable by default: `id` never changes, so page 2 is the
  # same page it was a minute ago. The float is added in front of it, not
  # instead of it, so ties within the floated group still read newest
  # first.
  def order(scope)
    return scope.order(id: :desc) unless ActiveModel::Type::Boolean.new.cast(params[:needs_action_first])

    scope.order(SubmissionRequest.needs_submitter_action_order, id: :desc)
  end

  # Multi-select list filters (db / status). The web client omits the
  # param entirely when every box (or none) is checked, so a present
  # param is always a proper subset — see EnumFilterable for what a value
  # outside the set gets.
  def filter_by_db(scope, raw)
    filter_by_enum(scope, :db, raw, SubmissionRequest.dbs.keys)
  end

  def filter_by_status(scope, raw)
    filter_by_enum(scope, :status, raw, SubmissionRequest.statuses.keys)
  end

  # Default to the live half: it is the one with anything to do in it.
  # `all` stays available for a submitter who wants the single stream
  # back, and an unknown value falls through to it rather than 400-ing on
  # a bookmarked URL.
  def filter_by_phase(scope, raw)
    case raw.to_s
    when 'finished' then scope.finished
    when 'all'      then scope
    else                 scope.unfinished
    end
  end

  def request_params
    params.expect(submission_request: %i[db ddbj_record])
  end
end
