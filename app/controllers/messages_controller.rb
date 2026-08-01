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
    attrs = params.expect(submission_message: [:body, {files: []}])

    @message = @request.messages.create!(
      user:        current_user,
      author_role: :submitter,
      body:        attrs[:body].to_s.strip,
      files:       Array(attrs[:files]).compact_blank
    )

    # Answering is dealing with what was asked, so it discharges the
    # thread. It has to be said here now that reading no longer does it.
    #
    # Only what was already there: a question that arrived while the
    # reply was being typed has not been answered by it, and marking it
    # read is the same lost reminder this whole change exists to stop,
    # just in a narrower window.
    mark_read(through: @message.id)

    # Writing in a thread you had put down is picking it back up. Left
    # closed, the request would carry on saying "You closed this" over a
    # live conversation, and stay on the finished side of the list while
    # the submitter waits for an answer.
    @request.reopen_if_closed!

    SubmissionMessageMailer.with(message: @message).notify_curators.deliver_later

    render :show, status: :created
  end

  # "Nothing to answer here." The other way a thread is dealt with — a
  # curator's note that needs no reply would otherwise sit in the
  # submitter's queue for ever, which is the trap the old auto-mark was
  # avoiding by discharging too much.
  def read
    mark_read(through: params[:through_id])

    head :no_content
  end

  private

  # Cheap UPDATE — at most touches the un-stamped tail of the thread.
  #
  # `through` bounds it to what the submitter had in front of them, so a
  # message that landed a moment ago is not discharged by an act that
  # could not have taken it into account. Absent, it means the whole
  # thread — a client that does not say what it saw gets the old
  # behaviour rather than an error.
  def mark_read(through: nil)
    scope = @request.messages.curator_role.unread
    scope = scope.where(id: ..through.to_i) if through.present?

    scope.update_all(read_at: Time.current)
  end

  # Scopes to the submitter's own requests, so a submitter cannot peek
  # at someone else's thread by guessing IDs — `find` raises a 404
  # instead of 403 to avoid disclosing existence.
  def load_submission_request
    @request = current_user.submission_requests.find(params[:submission_request_id])
  end
end
