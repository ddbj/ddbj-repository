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

  # Taking a submission out of the set takes its accessions off the set's
  # review link.
  #
  # Not what stops a reviewer seeing them — the link resolves what it
  # carries through the set's current contents, so they are gone the
  # moment this row is. What this stops is their coming back: without it,
  # putting the submission in again would quietly re-share whatever was
  # named on the link the last time it was here.
  after_destroy :unshare_accessions

  private

  # Looks in all three tables rather than in the one this submission's
  # database uses, because that is what resolves the link
  # (SubmissionSet#accession_rows). Asking a narrower question here than
  # the read path asks is how an accession comes to be left behind and
  # re-shared later — the exact thing this exists to prevent.
  #
  # Three DELETEs, each driven by a subquery: neither side comes back to
  # Ruby to be compared here. Both of them can be enormous — a link has no
  # ceiling and a BioSample submission can carry a hundred thousand
  # samples — and this runs once per inclusion, so for a departing member
  # it runs once per submission of theirs, inside the set's lock.
  def unshare_accessions
    access        = set.reviewer_access or return
    submission_id = submission_request.submission_id or return

    Submission.accession_row_models.each do |model|
      access.shared_accessions
              .where(accession: model.where(submission_id:).where.not(accession: nil).select(:accession))
              .delete_all
    end
  end

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
