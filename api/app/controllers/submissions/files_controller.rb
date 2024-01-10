class Submissions::FilesController < ApplicationController
  include FileDownload

  def show
    submission = current_user.submissions.find(params[:submission_id].delete_prefix('X-'))

    redirect_to find_file(submission.request.objs).url, allow_other_host: true
  end
end
