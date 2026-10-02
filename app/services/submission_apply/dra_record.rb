# A DRA record: its submission becomes the submission's DRASubmission row,
# and the files its runs and analyses name are assigned it from its
# submitter's uploads (DRA::RecordFiles) — the reads stay where they were
# uploaded, and the submission holds the same blobs. Assigned, they leave
# the uploader's list in the same commit: what is listed there is what is
# still waiting.
#
# Matched again here rather than taken from the check: the uploads can have
# changed since — a file taken out of the list, let go of when nothing was
# assigned it in time, or assigned to another of the uploader's submissions
# meanwhile. The uploader's row is locked while matching and assigning, so
# two of their requests applied at once cannot both be assigned one upload.
# Matched in the record as sent, so a file that has gone is named where the
# submitter put it rather than where canonical order did.
class SubmissionApply::DRARecord < SubmissionApply::V3Record
  class FilesGone < StandardError; end

  private

  def build_rows(submission, tree)
    user = @request.user.lock!

    files = DRA::RecordFiles.new(@sent, user)

    if (gone = files.unmatched).any?
      raise FilesGone, gone.map { "#{it.where} #{it.problem}" }.join('; ')
    end

    DRASubmission.create!(submission:, status: :submission_accepted, hold_date: tree.dig('submission', 'hold_date'))

    blobs = files.entries.map(&:blob)

    # Attachment rows rather than `attach`, which saves the submission — and
    # a submission saved without a ddbj_record fails its validation.
    blobs.each do |blob|
      submission.data_files_attachments.create! blob:
    end

    user.unassigned_files_attachments.where(blob: blobs).destroy_all
  end
end
