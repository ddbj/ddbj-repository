# A curator has worked on this request — replied to the submitter, edited
# the record, issued an accession.
#
# Deliberately not a permission and not a responsibility: participation
# grants nothing, and it never moves an assignment. All it decides is
# whether the request keeps surfacing in that curator's queue, which is
# why it can be written from anywhere without anyone having to think
# about the consequences.
#
# Append-only, like CurationEvent. Rows are never edited or removed.
class SubmissionRequestParticipant < ApplicationRecord
  belongs_to :submission_request
  belongs_to :user
end
