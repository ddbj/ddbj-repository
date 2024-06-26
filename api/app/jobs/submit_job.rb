class SubmitJob < ApplicationJob
  def perform(submission)
    submitter = "Database::#{submission.validation.db}::Submitter".constantize.new

    submitter.submit submission

    submission.validation.write_submission_files to: submission.dir
  end
end
