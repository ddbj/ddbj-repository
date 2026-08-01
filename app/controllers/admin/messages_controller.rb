module Admin
  # Curator side of the per-request curator ↔ submitter thread.
  # Submitter side is the public API MessagesController.
  #
  # Redirects back to the Messages tab the form lives on, so sending a
  # reply does not bounce the curator off the thread they were reading.
  class MessagesController < ApplicationController
    # "I know about this." The other way a thread is discharged — a reply
    # a curator has read and does not need to answer would otherwise sit
    # in their queue for ever, which is the trap the old open-marks-read
    # was avoiding by discharging it for everyone at once.
    def read
      request = SubmissionRequest.find(params[:submission_request_id])

      request.mark_read_by!(current_user, through: params[:through_id])

      redirect_to messages_admin_submission_request_path(request), notice: 'Marked as read.'
    end

    def create
      request = SubmissionRequest.find(params[:submission_request_id])
      body    = params.dig(:submission_message, :body).to_s.strip

      if body.blank?
        redirect_to messages_admin_submission_request_path(request), alert: 'Message body cannot be blank.'
        return
      end

      cc = cc_users(request)

      message = request.messages.create!(
        user:        current_user,
        author_role: :curator,
        body:        body,
        cc_user_ids: cc.map(&:id)
      )

      # Copied-in curators follow it from here, which is what makes the
      # submitter's next reply reach them. Told now as well as followed:
      # a request with nothing unanswered says nothing in a queue, and
      # "look at this" is not something to learn about later.
      cc.each { request.subscribe!(it) }

      SubmissionMessageMailer.with(message:).copied_in.deliver_later if cc.any?

      # Answering is having dealt with what was asked, so it discharges
      # the thread for this curator — and follows it, including for one
      # who had stopped: stepping back in is stepping back in.
      request.subscribe!(current_user)
      request.mark_read_by!(current_user, through: params[:through_id])

      # Asking something reopens a request the submitter had put down.
      # Otherwise the mail goes out and the app shows nothing: no banner,
      # no "needs you", and not even a row in the default list.
      request.reopen_if_closed!

      SubmissionMessageMailer.with(message:).notify_submitter.deliver_later

      notice = 'Message sent to submitter.'
      notice += " #{cc.map(&:uid).to_sentence} copied in." if cc.any?

      redirect_to messages_admin_submission_request_path(request), notice:
    end

    private

    # Admins other than the sender, from what the form offered. Anything
    # else in the params is dropped rather than refused: copying somebody
    # in is a courtesy on top of the message, and it must not be able to
    # stop the message being sent.
    def cc_users(request)
      ids = Array(params[:cc_user_ids]).map(&:to_i)

      User.staff.where(id: ids).where.not(id: current_user.id).order(:uid).to_a
    end
  end
end
