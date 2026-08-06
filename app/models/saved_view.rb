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

  # Values this view names that no longer exist: a status renamed, a
  # curator who has left. The ledger drops unknown values rather than
  # refusing them, which is right for a typed URL and wrong for a saved
  # one — dropped silently, a view that meant "assigned to Tanaka"
  # quietly becomes "everything". So it is said on the chip instead.
  #
  # `assignee_ids` is passed in rather than queried per view: the chip
  # row renders every view the curator has, and each would otherwise
  # cost a query to answer the same question.
  def unknown_values(assignee_ids:)
    RequestFilter.universes(assignee_ids).filter_map {|key, known|
      gone = Array(filters[key]) - known

      [key, gone] if gone.any?
    }.to_h
  end

  # True where a whole facet has gone unknown, which is the only case
  # that widens the view: the ledger drops what it does not recognise, so
  # a facet with nothing left to filter on stops filtering. A facet that
  # lost some of its values still constrains, on the ones that remain.
  def widened_by?(unknown)
    unknown.any? {|key, gone| gone.size == Array(filters[key]).size }
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
