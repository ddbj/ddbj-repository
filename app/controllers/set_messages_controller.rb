# The set's own thread, from a member's side. Curator side is
# Admin::SetMessagesController.
#
# Every member reads and writes it — being on the roster is the whole
# permission, as with everything else a set carries. What it deliberately
# does NOT carry is the per-submission conversations: those stay between
# one submitter and DDBJ (see MessageFilesController for the same line).
class SetMessagesController < ApplicationController
  include SetContents

  before_action :refuse_proxy!, only: %i[create]
  before_action :load_set

  def index
    @messages = @set.messages.includes(:user, files_attachments: :blob).to_a
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
    @set.mark_read_by!(current_user, through: @message.id)

    SubmissionSetMessageMailer.with(message: @message).notify_curators.deliver_later

    render :show, status: :created
  end

  # "Nothing to answer here." A curator's note that needs no reply would
  # otherwise sit in every member's queue for ever.
  def read
    @set.mark_read_by!(current_user, through: params[:through_id])

    head :no_content
  end

  private

  # Signed ids only — a malformed shape (`files[a]=b` arrives as
  # Parameters rather than an Array) is a bad request rather than a 500
  # at the model write.
  def signed_ids(raw)
    return [] unless raw.is_a?(Array)

    raw.compact_blank.filter_map { it if it.is_a?(String) }
  end

  # A set you are not in is not visible as a set you are not in.
  def load_set
    @set = SubmissionSet.joined_by(current_user).find(params.expect(:set_id))
  end
end
