module Admin
  # Curator side of the per-request curator ↔ submitter thread.
  # Submitter side is the public API MessagesController.
  #
  # Redirects back to the Messages tab the form lives on, so sending a
  # reply does not bounce the curator off the thread they were reading.
  class MessagesController < ApplicationController
    def create
      request = SubmissionRequest.find(params[:submission_request_id])
      body    = params.dig(:submission_message, :body).to_s.strip

      if body.blank?
        redirect_to messages_admin_submission_request_path(request), alert: 'Message body cannot be blank.'
        return
      end

      message = request.messages.create!(
        user:        current_user,
        author_role: :curator,
        body:        body
      )

      SubmissionMessageMailer.with(message:).notify_submitter.deliver_later

      redirect_to messages_admin_submission_request_path(request), notice: 'Message sent to submitter.'
    end
  end
end
