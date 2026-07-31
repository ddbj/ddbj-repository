class MessagesController < ApplicationController
  before_action :load_submission_request

  # Reading the thread no longer marks it read. "I have seen this" and "I
  # have dealt with this" are different events, and discharging the second
  # as a side effect of the first meant a submitter who opened a question
  # meaning to answer it later lost the only reminder they had — while a
  # curator waiting on that answer saw nothing either, because their queue
  # tracks unread SUBMITTER messages. The conversation just went quiet.
  def index
    @messages = @request.messages.includes(:user).to_a
  end

  def create
    @message = @request.messages.create!(
      user:        current_user,
      author_role: :submitter,
      body:        params.require(:submission_message).fetch(:body).to_s.strip
    )

    # Answering is dealing with what was asked, so it discharges the
    # thread. It has to be said here now that reading no longer does it.
    mark_read

    SubmissionMessageMailer.with(message: @message).notify_curators.deliver_later

    render :show, status: :created
  end

  # "Nothing to answer here." The other way a thread is dealt with — a
  # curator's note that needs no reply would otherwise sit in the
  # submitter's queue for ever, which is the trap the old auto-mark was
  # avoiding by discharging too much.
  def read
    mark_read

    head :no_content
  end

  private

  # Cheap UPDATE — at most touches the un-stamped tail of the thread.
  def mark_read
    @request.messages.curator_role.unread.update_all(read_at: Time.current)
  end

  # Scopes to the submitter's own requests, so a submitter cannot peek
  # at someone else's thread by guessing IDs — `find` raises a 404
  # instead of 403 to avoid disclosing existence.
  def load_submission_request
    @request = current_user.submission_requests.find(params[:submission_request_id])
  end
end
