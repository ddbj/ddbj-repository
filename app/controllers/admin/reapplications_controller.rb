module Admin
  # Applying a request again after its application failed, once a curator
  # has put right what it failed on (SubmissionRequest#apply_again).
  class ReapplicationsController < ApplicationController
    def create
      request = SubmissionRequest.find(params[:submission_request_id])

      if (blocked = request.apply_again)
        redirect_to admin_submission_request_path(request), alert: "Not applied again: #{blocked}"
      else
        participate! request

        redirect_to admin_submission_request_path(request), notice: "Applying request ##{request.id} again."
      end
    end
  end
end
