class ValidateSubmissionRequestJob < ApplicationJob
  def perform(request)
    DDBJRecordValidator.validate request
  end
end
