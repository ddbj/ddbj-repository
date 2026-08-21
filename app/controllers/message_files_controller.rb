# A file attached to a message in the curator ↔ submitter thread.
#
# Owner-scoped, not readable-scoped: the conversation is between one
# submitter and DDBJ, and being able to read somebody's submission
# through a shared set is not being party to it. The same line the
# messages endpoints draw.
class MessageFilesController < ApplicationController
  include AttachmentDownload

  def show
    submission_request = current_user.submission_requests.find(params.expect(:submission_request_id))
    message            = submission_request.messages.find(params.expect(:message_id))

    # Scoped to the message, so an attachment id from another thread is
    # not found rather than served.
    redirect_to_attachment message.files.find(params.expect(:id))
  end
end
