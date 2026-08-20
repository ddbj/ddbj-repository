# Downloads for curators. Everything a submitter's own routes serve, plus
# the message attachments, without the ownership scoping — a curator's
# reach over submissions is the premise of the admin section.
#
# Separate from the API's controllers because the way in is different: a
# session cookie rather than a token, which is the whole reason the two
# logins were made independent.
class Admin::FilesController < Admin::ApplicationController
  include AttachmentDownload

  REQUEST_NAMES = {'ddbj_record' => :ddbj_record}.freeze

  SUBMISSION_NAMES = {
    'ddbj_record' => :ddbj_record,
    'flatfile_na' => :flatfile_na,
    'flatfile_aa' => :flatfile_aa
  }.freeze

  def submission_request
    request = SubmissionRequest.find(params.expect(:submission_request_id))

    redirect_to_attachment request.public_send(REQUEST_NAMES.fetch(params[:name]))
  end

  def submission
    submission = Submission.find(params.expect(:submission_id))

    redirect_to_attachment submission.public_send(SUBMISSION_NAMES.fetch(params[:name]))
  end

  def message
    message = SubmissionMessage.find(params.expect(:message_id))

    redirect_to_attachment message.files.find(params.expect(:id))
  end
end
