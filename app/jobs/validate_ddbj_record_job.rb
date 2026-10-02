# Checking a record, by where its database's rules are: ST.26's here,
# BioProject's, BioSample's and DRA's in ddbj-validator. Any other database
# has no check to run yet, and is refused loudly rather than sent where it
# would be refused.
class ValidateDDBJRecordJob < ApplicationJob
  def perform(subject)
    # Only while the subject waits for this check. A job stopped part way
    # is run again from the start (RecoverKilledJobsJob), and run late — the
    # check having concluded before it was stopped — it would take back an
    # answer, perhaps from a request already sent.
    return unless subject.waiting_validation? || subject.validating?

    case subject.db
    when 'st26'                           then DDBJRecordValidator.validate subject
    when 'bioproject', 'biosample', 'dra' then DDBJValidatorCheck.start subject
    else raise ArgumentError, "no check for #{subject.db} records"
    end
  end
end
