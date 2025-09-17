class SubmitJob < ApplicationJob
  def perform(submission)
    submission.update! progress: :running, started_at: Time.current

    submitter = Database::MAPPING.fetch(submission.validation.db)::Submitter.new

    begin
      submitter.submit submission
    rescue => e
      Rails.error.report e

      submission.update!(
        result:        :failure,
        error_message: e.message
      )
    else
      submission.validation.write_submission_files to: submission.dir
      submission.success!
    end
  ensure
    submission.update! progress: :finished, finished_at: Time.current
  end
end
