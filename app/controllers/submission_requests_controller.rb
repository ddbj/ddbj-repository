class SubmissionRequestsController < ApplicationController
  include SourceIdFilterable
  include AccessionFilterable

  # The submitter's list, organised around "where is this now".
  #
  # Two things a plain reverse-id list got wrong. Submissions that are
  # finished never stop taking up room — a lab with 500 released records
  # cannot see the three that are still moving — so `phase` splits the
  # live ones from the done ones and the counts for both ride along in
  # headers. And anything waiting on the submitter has to float to the top
  # of the WHOLE list rather than of whichever page they happen to open,
  # which is why the ordering is a SQL predicate and not a client sort.
  def index
    owned = current_user.submission_requests

    scope = owned.includes(submission: %i[project accessions])
    scope = filter_by_phase(scope, params[:phase])
    scope = filter_by_db(scope, params[:db])               if params[:db].present?
    scope = filter_by_status(scope, params[:status])       if params[:status].present?
    scope = filter_by_source_id(scope, params[:source_id]) if params[:source_id].present?
    scope = filter_by_accession(scope, params[:accession]) if params[:accession].present?
    scope = scope.needs_submitter_action                   if params[:needs_action].present?

    ordered = scope.order(Arel.sql("(#{SubmissionRequest.needs_submitter_action_sql}) DESC"), id: :desc)

    pagy, @requests = pagy(ordered)

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

    response.headers.merge! pagy.headers_hash
    response.headers['Unfinished-Count'] = owned.unfinished.count.to_s
    response.headers['Finished-Count']   = owned.finished.count.to_s
  end

  def show
    @request = current_user.submission_requests.find(params.expect(:id))
  end

  def create
    @request = current_user.submission_requests.create!(**request_params)

    raise ActiveRecord::RecordInvalid unless @request.waiting_validation?

    ValidateDDBJRecordJob.perform_later @request

    render :show, status: :accepted
  end

  private

  # Multi-select list filters (db / status). The web client omits the
  # param entirely when every box (or none) is checked, so a present
  # param is always a proper subset. Unknown values are dropped so a
  # crafted param can't raise on the enum coercion.
  def filter_by_db(scope, raw)
    values = Array(raw).map(&:to_s) & SubmissionRequest.dbs.keys
    values.empty? ? scope : scope.where(db: values)
  end

  def filter_by_status(scope, raw)
    values = Array(raw).map(&:to_s) & SubmissionRequest.statuses.keys
    values.empty? ? scope : scope.where(status: values)
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

  # {submission_id => [first_accession, count]} for BS submissions, via one
  # grouped MIN / COUNT over sample accessions.
  def sample_accession_summaries(submissions)
    bs_ids = submissions.select(&:biosample_db?).map(&:id)
    return {} if bs_ids.empty?

    Sample
      .where(submission_id: bs_ids)
      .group(:submission_id)
      .pluck(:submission_id, Arel.sql('MIN(accession)'), Arel.sql('COUNT(accession)'))
      .to_h {|sid, first, count| [sid, [first, count]] }
  end

  def request_params
    params.expect(submission_request: %i[db ddbj_record])
  end
end
