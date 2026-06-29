module Admin
  # Curator side of the per-submission curator ↔ submitter thread.
  # Submitter side is the public API MessagesController.
  class MessagesController < ApplicationController
    def create
      submission = Submission.find(params[:submission_id])
      body       = params.dig(:submission_message, :body).to_s.strip

      if body.blank?
        redirect_to admin_submission_path(submission), alert: 'Message body cannot be blank.'
        return
      end

      message = submission.messages.create!(
        user:        current_user,
        author_role: :curator,
        body:        body
      )

      SubmissionMessageMailer.with(message:).notify_submitter.deliver_later

      redirect_to admin_submission_path(submission), notice: 'Message sent to submitter.'
    end
  end
end
