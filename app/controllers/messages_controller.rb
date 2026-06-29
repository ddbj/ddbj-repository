class MessagesController < ApplicationController
  before_action :load_submission

  def index
    @messages = @submission.messages.includes(:user).to_a

    # Mark unread curator-authored messages as read by the submitter.
    # Cheap UPDATE — at most touches the un-stamped tail of the thread.
    @submission.messages.curator_role.unread.update_all(read_at: Time.current)
  end

  def create
    @message = @submission.messages.create!(
      user:        current_user,
      author_role: :submitter,
      body:        params.require(:submission_message).fetch(:body).to_s.strip
    )

    SubmissionMessageMailer.with(message: @message).notify_curators.deliver_later

    render :show, status: :created
  end

  private

  # Scopes to the submitter's own submissions, so a submitter cannot
  # peek at someone else's thread by guessing IDs — `find` raises a
  # 404 instead of 403 to avoid disclosing existence.
  def load_submission
    @submission = current_user.submissions.find(params[:submission_id])
  end
end
