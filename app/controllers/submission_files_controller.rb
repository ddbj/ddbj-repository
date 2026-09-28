# What came out of applying a submission (AttachmentDownload::SUBMISSION_FILES).
class SubmissionFilesController < ApplicationController
  include AttachmentDownload

  def show
    submission = Submission.readable_by(current_user).find(params.expect(:submission_id))

    redirect_to_submission_file submission, params[:name]
  end
end
