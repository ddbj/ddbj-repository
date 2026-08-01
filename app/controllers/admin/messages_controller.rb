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
      files   = signed_ids(params[:files])

      # A message that is only an attachment is a real thing to send —
      # "here is the corrected file" needs no prose — so blank is only
      # refused when there is nothing at all.
      if body.blank? && files.empty?
        redirect_to messages_admin_submission_request_path(request), alert: 'Write something or attach a file.'
        return
      end

      cc = cc_users

      message = request.messages.create!(
        user:        current_user,
        author_role: :curator,
        body:        body,
        cc_user_ids: cc.map(&:id),
        files:       files
      )

      # Copied-in curators follow it from here, which is what makes the
      # submitter's next reply reach them. Told now as well as followed:
      # a request with nothing unanswered says nothing in a queue, and
      # "look at this" is not something to learn about later.
      cc.each { request.subscribe!(it) }

      SubmissionMessageMailer.with(message:).copied_in.deliver_later if cc.any?

      # And everyone already following, who would otherwise learn nothing:
      # answering settles the thread, so it leaves their queue at the same
      # moment it stops needing anyone.
      if request.followers_to_notify(message).any?
        SubmissionMessageMailer.with(message:).followed_activity.deliver_later
      end

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
    # Signed ids only. A malformed shape — `files[a]=b` arrives as
    # Parameters rather than an Array — would otherwise reach the model
    # write and come back as a 500, and an id that fails verification is
    # a bad request rather than a fault.
    def signed_ids(raw)
      return [] unless raw.is_a?(Array)

      raw.compact_blank.filter_map { it if it.is_a?(String) }
    end

    def cc_users
      ids = Array(params[:cc_user_ids]).map(&:to_i)

      User.staff.where(id: ids).where.not(id: current_user.id).order(:uid).to_a
    end
  end
end
