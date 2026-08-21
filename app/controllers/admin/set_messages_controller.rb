module Admin
  # Curator side of a set's thread. Member side is the public API's
  # SetMessagesController.
  class SetMessagesController < ApplicationController
    before_action :load_set

    def create
      body  = params.dig(:submission_set_message, :body).to_s.strip
      files = signed_ids(params[:files])

      if body.blank? && files.empty?
        redirect_to admin_set_path(@set), alert: 'Write something or attach a file.'
        return
      end

      message = @set.messages.create!(user: current_user, author_role: :curator, body:, files:)

      # Everyone in the set hears about it — see
      # SubmissionSetMessageMailer for what that costs at size.
      SubmissionSetMessageMailer.with(message:).notify_members.deliver_later

      # And the colleagues following it, who would otherwise learn
      # nothing: answering settles the thread, so it leaves their queue
      # at the same moment it stops needing anyone.
      if @set.followers_to_notify(message).any?
        SubmissionSetMessageMailer.with(message:).followed_activity.deliver_later
      end

      # Answering is having dealt with what was asked, and it follows the
      # set from here on — including for a curator who had stopped.
      @set.subscribe!(current_user)
      @set.mark_read_by!(current_user, through: params[:through_id])

      redirect_to admin_set_path(@set), notice: "Message sent to the #{@set.users.size} members of this set."
    end

    # "I know about this." A member's message a curator has read and does
    # not need to answer would otherwise sit in their queue for ever.
    def read
      @set.mark_read_by!(current_user, through: params[:through_id])

      redirect_to admin_set_path(@set), notice: 'Marked as read.'
    end

    private

    def load_set = @set = SubmissionSet.find(params.expect(:set_id))

    # Signed ids only — a malformed shape is a bad request rather than a
    # 500 at the model write.
    def signed_ids(raw)
      return [] unless raw.is_a?(Array)

      raw.compact_blank.filter_map { it if it.is_a?(String) }
    end
  end
end
