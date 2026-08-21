# A file attached to a message in a set's thread.
#
# Membership-scoped, unlike the per-request thread's attachments: this
# conversation is the set's, and everybody on the roster is party to it.
class SetMessageFilesController < ApplicationController
  include AttachmentDownload

  def show
    set     = SubmissionSet.joined_by(current_user).find(params.expect(:set_id))
    message = set.messages.find(params.expect(:message_id))

    # Scoped to the message, so an attachment id from another thread is
    # not found rather than served.
    redirect_to_attachment message.files.find(params.expect(:id))
  end
end
