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

      # Asking something reopens a request the submitter had put down.
      # Otherwise the mail goes out and the app shows nothing: no banner,
      # no "needs you", and not even a row in the default list.
      request.reopen_if_closed!

      SubmissionMessageMailer.with(message:).notify_submitter.deliver_later

      participate!(request)

      redirect_to messages_admin_submission_request_path(request), notice: 'Message sent to submitter.'
    end
  end
end
