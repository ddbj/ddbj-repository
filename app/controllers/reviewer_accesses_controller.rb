class ReviewerAccessesController < ApplicationController
  before_action :set_request

  def show
    @reviewer_access = @request.reviewer_access
  end

  # Enabling regenerates: any existing link is dropped and a fresh token is
  # minted, so re-enabling invalidates the old URL. Wrapped in a
  # transaction so a rejected new link (e.g. a past expires_at) rolls the
  # drop back and leaves the existing link intact.
  def create
    @reviewer_access = ReviewerAccess.transaction do
      @request.reviewer_access&.destroy!
      ReviewerAccess.create!(submission_request: @request, **reviewer_access_params)
    end

    render :show, status: :created
  end

  def destroy
    @request.reviewer_access&.destroy!

    head :no_content
  end

  private

  def set_request
    @request = current_user.submission_requests.find(params.expect(:submission_request_id))
  end

  def reviewer_access_params
    params.expect(reviewer_access: %i[expires_at])
  end
end
