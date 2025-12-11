class ValidateDDBJRecordJob < ApplicationJob
  def perform(subject)
    DDBJRecordValidator.validate subject
  end
end
