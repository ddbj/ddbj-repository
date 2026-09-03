# One accession named on a set's review link.
#
# The accession number, not a reference to the row it names. Three
# databases keep three different rows — a Project, a Sample, an Entry —
# so a foreign key here would have to be polymorphic, and it would go on
# pointing at the row after the submission holding it had been taken out
# of the set. The number resolves through the set instead (see
# ReviewerAccess#shared_rows), which is what makes leaving the set take
# the accession off the link.
#
# It is also what a submitter has in hand. The accessions on a review link
# are often the ones written in the manuscript, typed in rather than
# picked — which is why they can be pasted as well as ticked.
class ReviewerAccessAccession < ApplicationRecord
  belongs_to :reviewer_access

  # The owner of the submission it belongs to — nobody else can put an
  # accession here. Kept alongside that rule rather than derived from it:
  # ownership is re-checked from the row on every write, and this is the
  # record of who actually pressed the button.
  belongs_to :added_by, class_name: 'User'

  # Also a unique index. The validation is what turns a double press into
  # "it is already there" rather than a 500.
  validates :accession, presence: true, uniqueness: {scope: :reviewer_access_id}
end
