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
  # The universe each facet is chosen from — the same sets the ledger
  # measures a selection against. `assignee` needs a query, so it is
  # passed in: the chip row normalises once per view and would otherwise
  # ask the same question every time.
  def self.assignee_universe = ['0'] + User.staff.pluck(:id).map(&:to_s)

  def self.universes(assignee_ids)
    {
      'db'             => SubmissionRequest.dbs.keys,
      'request_status' => SubmissionRequest.statuses.keys,
      'status'         => Lifecycleable::STATUSES.keys,
      'assignee'       => assignee_ids
    }
  end

  def self.normalise(params, assignee_ids: assignee_universe)
    universes = universes(assignee_ids)

    FILTERS.each_with_object({}) {|key, filters|
      raw = params[key]

      if MULTI.include?(key)
        values = Array.wrap(raw).grep(String).map(&:strip).reject(&:blank?).uniq

        # A facet with every box ticked is not a filter. The ledger reads
        # it as no constraint (see `full_or_empty?`), and its form posts
        # exactly that on a bare Search — every box is checked when the
        # param is absent — so without this, pressing Search and then
        # Save stores the whole ledger under the name of a filter.
        next if values.empty? || (universes.fetch(key) - values).empty?

        # Sorted, because a view is a set: the same two boxes ticked in
        # the other order is the same view, and `showing?` compares these
        # hashes.
        filters[key] = values.sort
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
  def showing?(params, assignee_ids: self.class.assignee_universe)
    filters == self.class.normalise(params, assignee_ids:)
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
    self.class.universes(assignee_ids).filter_map {|key, known|
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

  # Uids for the assignees a set of views name and the staff list no
  # longer has — a demoted or departed curator. Without it a chip would
  # report a bare database id, which tells the reader nothing.
  def self.assignee_labels(views, assignee_ids)
    ids = views.flat_map { it.unknown_values(assignee_ids:)['assignee'] }.compact.uniq
    return {} if ids.empty?

    User.where(id: ids).pluck(:id, :uid).to_h {|id, uid| [id.to_s, uid] }
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
