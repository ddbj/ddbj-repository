# A curator's relationship to one set's thread: whether it keeps
# reaching their queue, and how far they have read.
#
# The set-axis twin of SubmissionRequestParticipant, and deliberately the
# same shape — a curator who posts follows from then on, a colleague who
# only reads speaks for nobody but themselves, and a row is never
# removed because having worked here is a fact about the past.
#
# Members are not here. Being in the set is what makes the thread theirs
# to read, so there is nothing to subscribe to or unsubscribe from; their
# marker is on the roster row (SubmissionSetMember#last_read_at).
class SubmissionSetParticipant < ApplicationRecord
  belongs_to :set, class_name: 'SubmissionSet', foreign_key: :submission_set_id, inverse_of: :participations
  belongs_to :user

  scope :subscribed, -> { where(unsubscribed_at: nil) }
end
