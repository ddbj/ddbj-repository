# A curator has worked on this request — replied to the submitter, edited
# the record, issued an accession.
#
# Deliberately not a permission and not a responsibility: participation
# grants nothing, and it never moves an assignment. All it decides is
# whether the request keeps surfacing in that curator's queue, which is
# why it can be written from anywhere without anyone having to think
# about the consequences.
#
# It is also the subscription, in the GitHub sense: a row means "keep
# telling me about this one". `last_read_at` is how far that curator has
# got, so a colleague dealing with the thread no longer takes it out of
# their queue too. Nil means they have never marked anything read here.
#
# Rows are created but not removed. `last_read_at` is the one thing that
# moves.
class SubmissionRequestParticipant < ApplicationRecord
  belongs_to :submission_request
  belongs_to :user

  # Following it. The row survives unsubscribing — it still records that
  # this curator worked here — so everything that asks "whose queue does
  # this belong in" asks this rather than asking whether a row exists.
  scope :subscribed, -> { where(unsubscribed_at: nil) }
end
