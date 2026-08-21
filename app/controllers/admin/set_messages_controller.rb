module Admin
  # Curator side of a set's thread. Member side is the public API's
  # SetMessagesController.
  class SetMessagesController < ApplicationController
    include AttachmentSignedIds

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
      @set.mark_read_by!(current_user, as: :curator, through: params[:through_id])

      redirect_to admin_set_path(@set), notice: "Message sent to #{helpers.pluralize(@set.users.size, 'member')} of this set."
    end

    # "I know about this." A member's message a curator has read and does
    # not need to answer would otherwise sit in their queue for ever.
    def read
      # Reported from what actually happened: a `through_id` from a stale
      # tab names a message that is not in this thread, which marks
      # nothing — and saying "Marked as read." over a badge that is still
      # there is worse than saying nothing.
      if @set.mark_read_by!(current_user, as: :curator, through: params[:through_id])
        redirect_to admin_set_path(@set), notice: 'Marked as read.'
      else
        redirect_to admin_set_path(@set), alert: 'Nothing was marked — this page was drawn before the thread moved. Reload and look again.'
      end
    end

    private

    def load_set = @set = SubmissionSet.find(params.expect(:set_id))
  end
end
