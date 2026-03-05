class StatusesController < ApplicationController
  def show
    @request = current_user.submission_requests.find(params[:submission_request_id])
  end
end
