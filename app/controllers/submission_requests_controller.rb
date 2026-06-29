class SubmissionRequestsController < ApplicationController
  def index
    scope = current_user.submission_requests.includes(submission: :accessions)
    scope = scope.where(db: params[:db]) if params[:db].present?

    pagy, @requests = pagy(scope.order(id: :desc))

    # Pre-fetch the set of submissions with at least one unread curator
    # message so the view's `has_unread_curator_message` flag doesn't
    # N+1. One indexed query per page.
    submission_ids = @requests.filter_map { it.submission&.id }
    @unread_submission_ids =
      SubmissionMessage
        .curator_role.unread
        .where(submission_id: submission_ids)
        .distinct
        .pluck(:submission_id)
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

  def request_params
    params.expect(submission_request: %i[db ddbj_record])
  end
end
