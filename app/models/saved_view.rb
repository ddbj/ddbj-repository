# A name for a set of ledger filters, belonging to one curator.
#
# The ledger's whole state lives in the query string (that is the rule
# 11a settled), so a saved view needs to be nothing more than those
# params under a name — no stored SQL, no second way of expressing a
# filter, and nothing a view can mean that the screen cannot show.
#
# Personal rather than shared, for now. Adding "share with the team"
# later is a column; starting shared and retreating to personal would
# take views away from whoever had come to rely on them.
class SavedView < ApplicationRecord
  MAX_NAME_LENGTH = 60

  # The chip row has to stay one glance. Past this it is a list, and a
  # list wants a screen of its own — which is a decision to make when
  # somebody actually gets there, not now.
  MAX_PER_USER = 20

  belongs_to :user

  validates :name, presence: true, length: {maximum: MAX_NAME_LENGTH},
                   uniqueness: {scope: :user_id, case_sensitive: false}

  validate :filters_present
  validate :within_limit, on: :create

  scope :ordered, -> { order(:name) }

  # What to put in the link. Symbol keys, because that is what the route
  # helpers take.
  def to_query = filters.symbolize_keys

  # Whether the screen is currently showing this view. Compared against
  # the normalised form of what is on screen so "?db=biosample&page=2"
  # still counts — the page is not part of the view.
  def showing?(params, assignee_ids: nil)
    filters == RequestFilter.normalise(params, assignee_ids:)
  end

  # Everything that has happened to a view since it was saved, in the two
  # ways it can stop meaning what it meant.
  #
  # `assignee_ids` is passed in rather than queried per view: the chip row
  # renders every view the curator has, and each would otherwise cost a
  # query to answer the same question.
  # `widened` is worked out where the stored sets are still in hand: a
  # facet with nothing left to filter on stops filtering, and so does one
  # that now covers every option there is. A facet that merely lost some
  # of its values still constrains, on the ones that remain.
  Staleness = Data.define(:unknown, :ineffective, :widened) do
    def any? = unknown.any? || ineffective.any?
  end

  def staleness(assignee_ids:)
    universes = RequestFilter.universes(assignee_ids)

    # Values the view names that no longer exist: a status renamed, a
    # curator who has left. The ledger drops what it does not recognise,
    # so a view that meant "assigned to Tanaka" quietly becomes
    # "everything" — said on the chip rather than left to be noticed as a
    # quiet morning.
    unknown = universes.filter_map {|key, known|
      stored = Array(filters[key])
      gone   = stored - known

      [key, gone, stored] if gone.any?
    }

    # And the other direction, which nothing above can see: every value
    # still exists, but the set now covers the whole universe. A view
    # naming "unassigned or bob" while bob and dave were staff stops
    # narrowing anything the day dave is no longer staff — nothing became
    # unknown, the universe shrank to meet it.
    ineffective = universes.filter_map {|key, known|
      stored = Array(filters[key])

      key if stored.any? && (known - stored).empty?
    }

    Staleness.new(
      unknown:     unknown.to_h {|key, gone, _stored| [key, gone] },
      ineffective:,
      widened:     ineffective.any? || unknown.any? {|_key, gone, stored| gone.size == stored.size }
    )
  end

  # Names for every assignee this row of chips mentions, resolved once
  # rather than per view. A departed curator is the case that matters:
  # they have left the staff list, so the chip is stale, and a bare
  # database id in the explanation tells the reader nothing.
  def self.assignee_labels(views)
    RequestFilter.assignee_labels(views.flat_map { Array(it.filters['assignee']) }.uniq)
  end

  private

  # A view of everything is the ledger, which already has a link.
  def filters_present
    errors.add(:base, 'Nothing is filtered, so there is no view to save.') if filters.blank?
  end

  def within_limit
    return unless user && user.saved_views.count >= MAX_PER_USER

    errors.add(:base, "You already have #{MAX_PER_USER} saved views. Delete one before saving another.")
  end
end
