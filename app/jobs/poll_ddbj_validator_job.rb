# Asks ddbj-validator after a check it is running (DDBJValidatorCheck).
class PollDDBJValidatorJob < ApplicationJob
  # A check run again replaces this one, and takes this job's place.
  discard_on ActiveJob::DeserializationError

  def perform(validation, attempt)
    DDBJValidatorCheck.poll validation, attempt
  end
end
