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
# are the ones written in the manuscript; they are typed in, not picked
# from a list of a hundred thousand samples.
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

  # The ceiling belongs to the link, so it is checked here rather than only
  # where a screen fills it. The bulk add counts before it inserts — one
  # query instead of one per row — and refuses with words; this is what
  # holds for everything else that puts a row here.
  validate :within_link_capacity, on: :create

  private

  def within_link_capacity
    return if reviewer_access.nil? || !reviewer_access.full?

    errors.add(:base, "A review link carries at most #{ReviewerAccess::MAX_SHARED} accessions.")
  end
end
