# Checking a record, by where its database's rules are: ST.26's here,
# BioProject's, BioSample's and DRA's in ddbj-validator. Any other database
# has no check to run yet, and is refused loudly rather than sent where it
# would be refused.
class ValidateDDBJRecordJob < ApplicationJob
  def perform(subject)
    case subject.db
    when 'st26'                           then DDBJRecordValidator.validate subject
    when 'bioproject', 'biosample', 'dra' then DDBJValidatorCheck.start subject
    else raise ArgumentError, "no check for #{subject.db} records"
    end
  end
end
