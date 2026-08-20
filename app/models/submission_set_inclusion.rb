# One submission's place in one set.
#
# Points at the SubmissionRequest rather than the Submission: the request
# is the unit everywhere else (see [[project-request-as-unit-deploy]]),
# and a conversation about a submission starts before Apply, when there
# is no Submission to point at. "Submission" is what a person calls it,
# which is why the table is not named after the request.
class SubmissionSetInclusion < ApplicationRecord
  # `set` is the word everywhere else — the class is SubmissionSet only
  # because Ruby owns the constant `Set`.
  belongs_to :set, class_name: 'SubmissionSet', foreign_key: :submission_set_id, inverse_of: :inclusions
  belongs_to :submission_request

  # Who put it here — which is always its owner, since only they can.
  # Kept anyway: an account can be proxied, and "who did this" is the
  # question a support thread asks.
  belongs_to :added_by, class_name: 'User'

  # Also a unique index. The validation is what turns a double press into
  # "it is already there" rather than a 500.
  validates :submission_request_id, uniqueness: {scope: :submission_set_id}

  validate :addable_by_adder

  private

  # Your own submission, and nobody else's. Reading somebody else's
  # through a shared set does not carry the right to hand it on to a
  # third set — the owner decides where their work is shared, every
  # time.
  def addable_by_adder
    return if submission_request.nil? || added_by.nil?
    return if submission_request.user_id == added_by_id

    errors.add(:submission_request, 'can only be added by its owner')
  end
end
