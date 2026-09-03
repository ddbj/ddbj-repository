# Everything in the set the caller could put on its review link.
#
# Their own, and only their own: an accession is shared by the owner of
# the submission it belongs to (SetSharedAccessionsController says why),
# so a candidate list that showed a colleague's work would be offering
# something the next request refuses.
#
# It exists because the alternative is knowing the numbers by heart. What
# goes on the link is written rather than picked — a number, or a range —
# and this is where somebody who does not have their numbers in front of
# them finds out what they are.
class SetAccessionsController < ApplicationController
  include SetContents

  before_action :load_set

  # Two steps, like every other list of accessions here: a page of numbers
  # out of the set, then the rows behind that page. The union that orders
  # them projects the number alone, because it spans three tables and
  # there is nothing else the three agree on.
  def index
    numbers = paginate(@set.owned_accessions(current_user)).map(&:accession)

    # Everything here is the reader's own, so nothing on this list prints
    # an owner and nothing needs one loaded.
    @rows = @set.accession_rows(numbers, with_owner: false)

    # Which of them are already on the link, so a row can say so rather
    # than being offered as if it were new. Bounded by the page, not by
    # the link.
    shared = @set.reviewer_access&.shared_accessions&.where(accession: numbers)&.pluck(:accession)

    @shared = Set.new(shared || [])
  end
end
