# What the ledger is actually filtered by, as opposed to what happened to
# arrive in the query string.
#
# The two differ on the most common route to the screen. The facet groups
# sit inside the search form and render every box checked when their
# param is absent, so pressing Search posts every value of every facet —
# which `full_or_empty?` reads as no constraint at all. A URL saying
# `db[]=st26&db[]=bioproject&db[]=biosample` and a bare `/admin/requests`
# are the same ledger, and everything that describes the screen has to
# agree about that: the badges beside the search box, the Clear link, the
# empty state's choice between "nothing matched" and "nothing here yet",
# and what a saved view stores.
#
# It lives here rather than on SavedView because it is the ledger's
# notion, not the saved view's — the chrome deciding whether to show a
# Clear link should not be asking a model about bookmarks.
class RequestFilter
  FILTERS = %w[q db request_status status assignee].freeze

  # Multi-select facets. Values are stored as arrays so a one-value
  # selection and a two-value selection have the same shape.
  MULTI = %w[db request_status status assignee].freeze

  ENUM_UNIVERSES = {
    'db'             => -> { SubmissionRequest.dbs.keys },
    'request_status' => -> { SubmissionRequest.statuses.keys },
    'status'         => -> { Lifecycleable::STATUSES.keys }
  }.freeze

  # `filter_by_assignee` spells "nobody has claimed this" as a value in
  # the same list as the user ids, because on screen it is one more box
  # to tick.
  UNASSIGNED = '0'

  class << self
    # "Unassigned" plus every staff id — the universe `filter_by_assignee`
    # measures a selection against.
    def assignee_universe = [UNASSIGNED] + User.staff.pluck(:id).map(&:to_s)

    # Assignee values are user ids, which say nothing to whoever reads
    # them back. Anywhere one is echoed — the badge row, a saved view's
    # chip — goes through here. A curator who has left the staff list is
    # still a User, so most of them still resolve; one whose row is gone
    # keeps its id rather than disappearing.
    def assignee_labels(values)
      ids = values.map(&:to_s) - [UNASSIGNED]
      map = ids.any? ? User.where(id: ids).pluck(:id, :uid).to_h {|id, uid| [id.to_s, uid] } : {}

      map.merge(UNASSIGNED => 'Unassigned')
    end

    def universes(assignee_ids)
      ENUM_UNIVERSES.transform_values(&:call).merge('assignee' => assignee_ids)
    end

    # Everything the ledger would narrow on, and nothing else.
    #
    # `assignee_ids` is passed in by callers that already have the staff
    # list — the chip row normalises once per view and would otherwise
    # ask the same question every time. Left out, it is queried lazily
    # and only when an assignee param is actually present, so the queues
    # that render this table without facets pay nothing.
    #
    # `grep(String)` rather than `to_s`: a query string can nest
    # (`?db[x]=y`), and a Parameters coerced to a String would become a
    # filter value that matches nothing and reads as gibberish wherever
    # it is echoed back.
    def normalise(params, assignee_ids: nil)
      FILTERS.each_with_object({}) {|key, filters|
        raw = params[key]

        if MULTI.include?(key)
          values = Array.wrap(raw).grep(String).map(&:strip).reject(&:blank?).uniq
          next if values.empty?

          assignee_ids ||= assignee_universe if key == 'assignee'
          universe       = key == 'assignee' ? assignee_ids : ENUM_UNIVERSES.fetch(key).call

          # Every box ticked is not a filter, and neither is none of them.
          next if (universe - values).empty?

          # Canonical order, because a facet is a set: the same two boxes
          # ticked in the other order is the same filter. In the order the
          # boxes themselves are in rather than alphabetically — this is
          # what gets read back on a badge and suggested as a view's name,
          # and "ST.26, BioSample" is the order the curator just ticked
          # them in. Anything the universe does not know goes last.
          filters[key] = values.sort_by { [universe.index(it) || universe.size, it] }
        else
          # Capped where the search caps it, so an echoed query cannot
          # claim more than the box it was typed into.
          value = raw.is_a?(String) ? raw.strip[0, Admin::RequestSearch::MAX_QUERY_LENGTH] : nil
          filters[key] = value if value.present?
        end
      }
    end

    # Just the facets, which is what the badge row and the empty state
    # describe — the search box shows the query itself.
    def facets(params, assignee_ids: nil)
      normalise(params, assignee_ids:).except('q')
    end
  end
end
