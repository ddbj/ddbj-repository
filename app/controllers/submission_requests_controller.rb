class SubmissionRequestsController < ApplicationController
  include SourceIdFilterable

  def index
    scope = current_user.submission_requests.includes(submission: :accessions)
    scope = filter_by_db(scope, params[:db])               if params[:db].present?
    scope = filter_by_status(scope, params[:status])       if params[:status].present?
    scope = filter_by_source_id(scope, params[:source_id]) if params[:source_id].present?

    pagy, @requests = pagy(scope.order(id: :desc))

    # Pre-fetch the set of requests with at least one unread curator
    # message so the view's `has_unread_curator_message` flag doesn't
    # N+1. One indexed query per page.
    @unread_request_ids =
      SubmissionMessage
        .curator_role.unread
        .where(submission_request_id: @requests.map(&:id))
        .distinct
        .pluck(:submission_request_id)
        .to_set

    response.headers.merge! pagy.headers_hash
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

  def request_params
    params.expect(submission_request: %i[db ddbj_record])
  end
end
