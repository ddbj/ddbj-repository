module Admin
  # Whether a request keeps surfacing in this curator's queue.
  #
  # Following is what acting on a request does — reply once to somebody
  # else's thread and it follows you from then on. Usually right, which is
  # why it is the default; but a curator drawn into something they have no
  # further part in needs a way out, or the queue fills with other
  # people's work and stops being read.
  #
  # Not offered to the assignee: owning a request is not a subscription
  # you can decline. Releasing it is how you stop owning it.
  class SubscriptionsController < ApplicationController
    before_action :set_request

    def create
      @request.subscribe!(current_user)

      redirect_back fallback_location: messages_admin_submission_request_path(@request),
                    notice: 'Following this request.'
    end

    def destroy
      if @request.assignee_id == current_user.id
        return redirect_back fallback_location: messages_admin_submission_request_path(@request),
                             alert: 'You are assigned to this request. Release it to stop following.'
      end

      @request.unsubscribe!(current_user)

      redirect_back fallback_location: messages_admin_submission_request_path(@request),
                    notice: 'No longer following this request.'
    end

    private

    def set_request
      @request = SubmissionRequest.find(params[:submission_request_id])
    end
  end
end
