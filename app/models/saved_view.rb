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
  # What the ledger filters on. Anything else in the query string —
  # `page` above all — is deliberately not here: a view is a set of
  # rows, not a position in it.
  FILTERS = %w[q db request_status status assignee].freeze

  # Multi-select facets. Stored as arrays so a one-value view and a
  # two-value view have the same shape.
  MULTI = %w[db request_status status assignee].freeze

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

  # Everything the ledger would accept, and nothing else. Values are
  # normalised on the way in so the stored view is already in the shape
  # the URL wants — the alternative is normalising on every render, and
  # then two views saved from the same screen can differ.
  #
  # `grep(String)` rather than `to_s`: a query string can nest
  # (`?db[x]=y`), and a Parameters coerced to a String would be stored as
  # a filter value that matches nothing and reads as gibberish on the
  # chip. Anything that is not a string was not something the ledger's
  # own form could have produced.
  def self.normalise(params)
    FILTERS.each_with_object({}) {|key, filters|
      raw = params[key]

      if MULTI.include?(key)
        values = Array.wrap(raw).grep(String).map(&:strip).reject(&:blank?).uniq
        filters[key] = values if values.any?
      else
        # Capped where the search caps it, so a stored query cannot mean
        # more than the box it was typed into.
        value = raw.is_a?(String) ? raw.strip[0, Admin::RequestSearch::MAX_QUERY_LENGTH] : nil
        filters[key] = value if value.present?
      end
    }
  end

  # What to put in the link. Symbol keys, because that is what the route
  # helpers take.
  def to_query = filters.symbolize_keys

  # Whether the screen is currently showing this view. Compared against
  # the normalised form of what is on screen so "?db=biosample&page=2"
  # still counts — the page is not part of the view.
  def showing?(params) = filters == self.class.normalise(params)

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
    {
      'db'             => Array(filters['db']) - SubmissionRequest.dbs.keys,
      'request_status' => Array(filters['request_status']) - SubmissionRequest.statuses.keys,
      'status'         => Array(filters['status']) - Lifecycleable::STATUSES.keys,
      'assignee'       => Array(filters['assignee']) - assignee_ids
    }.reject {|_key, values| values.empty? }
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
