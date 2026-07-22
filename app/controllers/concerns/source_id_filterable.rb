# Shared `source_id` list filter for controllers whose base relation is
# `submission_requests` (the public API index and the admin index). It's a
# case-insensitive PREFIX match on the applied submission's source_id via
# a correlated EXISTS, so a request with no submission yet naturally drops
# out. Non-String input is ignored (a crafted `?source_id[]=x`), and the
# value is length-capped to bound the ILIKE cost and log payload.
module SourceIdFilterable
  extend ActiveSupport::Concern

  MAX_SOURCE_ID_LENGTH = 64

  private

  def filter_by_source_id(scope, raw)
    return scope unless raw.is_a?(String)

    value = raw.strip[0, MAX_SOURCE_ID_LENGTH]
    return scope if value.blank?

    scope.where(<<~SQL.squish, pattern: "#{ActiveRecord::Base.sanitize_sql_like(value)}%")
      EXISTS (SELECT 1 FROM submissions WHERE submissions.id = submission_requests.submission_id AND submissions.source_id ILIKE :pattern)
    SQL
  end
end
