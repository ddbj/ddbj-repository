# The set's own thread, from a member's side. Curator side is
# Admin::SetMessagesController.
#
# Every member reads and writes it — being on the roster is the whole
# permission, as with everything else a set carries. What it deliberately
# does NOT carry is the per-submission conversations: those stay between
# one submitter and DDBJ (see MessageFilesController for the same line).
class SetMessagesController < ApplicationController
  include SetContents
  include AttachmentSignedIds
  include MessageThreadPaging

  # Both writes: `read` moves a marker on the member's own roster row,
  # which is that person's reminder and not a curator's to discharge
  # while acting as them.
  before_action :refuse_proxy!, only: %i[create read]
  before_action :load_set

  def index
    @messages = thread_page(@set.messages.includes(:user, files_attachments: :blob))
  end

  def create
    attrs = params.expect(submission_set_message: [:body, {files: []}])

    # Under the set's lock, and asked again inside it: a removal that
    # committed after the membership check would otherwise leave a
    # message from somebody no longer here, in a thread they can no
    # longer see.
    @message = within_submission_set_membership(@set) {
      @set.messages.create!(
        user:        current_user,
        author_role: :member,
        body:        attrs[:body].to_s.strip,
        files:       signed_ids(attrs[:files])
      )
    }

    # Writing is having dealt with what was there — the same rule as the
    # request thread, and only through what was already on screen.
    @set.mark_read_by!(current_user, as: :member, through: @message.id)

    # Both directions. The curators following it are being asked
    # something; the rest of the set is being told, because a message to
    # a set is to the people in it as much as to DDBJ — which is what the
    # screen promises when it says everyone here gets it.
    SubmissionSetMessageMailer.with(message: @message).notify_curators.deliver_later
    SubmissionSetMessageMailer.with(message: @message).notify_members.deliver_later

    render :show, status: :created
  end

  # "Nothing to answer here." A curator's note that needs no reply would
  # otherwise sit in every member's queue for ever.
  def read
    @set.mark_read_by!(current_user, as: :member, through: params[:through_id])

    head :no_content
  end

  private
end
