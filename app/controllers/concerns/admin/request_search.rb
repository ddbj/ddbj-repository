module Admin
  # The ledger's one search box.
  #
  # Six stacked checkbox facets used to occupy the screen above the table,
  # which meant arriving at "All requests" showed filters rather than
  # requests. Most lookups are not a facet combination at all — somebody
  # has an identifier in hand and wants that row. So the box takes any of
  # them and works out which it is, and the facets fold away behind it.
  #
  # Prefix matching (not `%q%`) so the existing per-column indexes can
  # still be used, and length-capped for the same reason as the individual
  # filters it subsumes.
  module RequestSearch
    extend ActiveSupport::Concern

    MAX_QUERY_LENGTH = 64

    private

    def filter_by_query(scope, raw)
      return scope unless raw.is_a?(String)

      value = raw.strip[0, MAX_QUERY_LENGTH]
      return scope if value.blank?

      # A bare number is a request id; anything else is an identifier or a
      # uid. COALESCE keeps the id branch harmless when it is neither.
      scope.where(<<~SQL.squish, id: Integer(value, exception: false), pattern: "#{ActiveRecord::Base.sanitize_sql_like(value)}%")
        submission_requests.id = COALESCE(:id, -1) OR
        EXISTS (SELECT 1 FROM users       WHERE users.id                 = submission_requests.user_id       AND users.uid            ILIKE :pattern) OR
        EXISTS (SELECT 1 FROM submissions WHERE submissions.id           = submission_requests.submission_id AND submissions.source_id ILIKE :pattern) OR
        EXISTS (SELECT 1 FROM projects    WHERE projects.submission_id   = submission_requests.submission_id AND projects.accession    ILIKE :pattern) OR
        EXISTS (SELECT 1 FROM samples     WHERE samples.submission_id    = submission_requests.submission_id AND samples.accession     ILIKE :pattern) OR
        EXISTS (SELECT 1 FROM entries  WHERE entries.submission_id = submission_requests.submission_id AND entries.number     ILIKE :pattern)
      SQL
    end
  end
end
