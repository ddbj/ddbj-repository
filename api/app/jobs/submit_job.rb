class SubmitJob < ApplicationJob
  def perform(submission)
    ActiveRecord::Base.transaction do
      submission.update! progress: :running, started_at: Time.current

      submitter = Database::MAPPING.fetch(submission.validation.db)::Submitter.new

      Rails.error.handle do
        begin
          submitter.submit submission
        rescue => e
          submission.update!(
            result:        :failure,
            error_message: e.message
          )

          raise
        else
          submission.validation.write_submission_files to: submission.dir
          submission.success!
        end
      end
    ensure
      submission.update! progress: :finished, finished_at: Time.current
    end
  end
end
