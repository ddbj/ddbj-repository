# Checking a record, by where its database's rules are: ST.26's here, the
# others' in ddbj-validator.
class ValidateDDBJRecordJob < ApplicationJob
  def perform(subject)
    if subject.db == 'st26'
      DDBJRecordValidator.validate subject
    else
      DDBJValidatorCheck.start subject
    end
  end
end
