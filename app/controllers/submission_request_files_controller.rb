# The file a submitter uploaded, for whoever may read the request.
#
# The attachment is named by the route rather than carried as a signed
# blob id, so there is no way to present one record's id with another
# record's blob — and an attachment no route names (SubmissionUpdate's
# patch, the materialised-record cache) has no way in at all.
class SubmissionRequestFilesController < ApplicationController
  include AttachmentDownload

  # The route constrains this too; the pair is deliberate. The constraint
  # keeps an unknown name from reaching Ruby, and the map keeps a `send`
  # on a path segment from ever being what resolves it.
  NAMES = {'ddbj_record' => :ddbj_record}.freeze

  def show
    # Readable, not owned: a set's members can read each other's
    # submissions, and the upload is part of that.
    submission_request = SubmissionRequest.readable_by(current_user).find(params.expect(:submission_request_id))

    redirect_to_attachment submission_request.public_send(NAMES.fetch(params[:name]))
  end
end
