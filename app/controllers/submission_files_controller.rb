# What came out of applying a submission: the record as stored, and the
# flatfiles rendered from it.
class SubmissionFilesController < ApplicationController
  include AttachmentDownload

  # `current_record` and `cached_materialised_record` are deliberately
  # absent. Nothing renders a link to them, and this is the list that
  # decides whether one could exist.
  NAMES = {
    'ddbj_record' => :ddbj_record,
    'flatfile_na' => :flatfile_na,
    'flatfile_aa' => :flatfile_aa
  }.freeze

  def show
    submission = Submission.readable_by(current_user).find(params.expect(:submission_id))

    redirect_to_attachment submission.public_send(NAMES.fetch(params[:name]))
  end
end
