class SubmitJob < ApplicationJob
  def perform(submission)
    submission.validation.write_submission_files to: submission.dir
  end
end
