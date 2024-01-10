class SubmitJob < ApplicationJob
  def perform(request)
    Validators.validate request do
      next unless request.validity == 'valid'

      submission = request.create_submission!

      request.write_submission_files to: submission.dir
    end
  end
end
