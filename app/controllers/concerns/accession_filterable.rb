# Shared `accession` list filter for controllers whose base relation is
# `submission_requests`. Case-insensitive PREFIX match OR-ed across the
# three accession-bearing sources — projects (BP), samples (BS), and the
# accessions table (ST.26) — via correlated EXISTS, so a request matches
# when the accession lives on any of them. Non-String input is ignored
# and the value is length-capped to bound the ILIKE cost / log payload.
module AccessionFilterable
  extend ActiveSupport::Concern

  MAX_ACCESSION_LENGTH = 64

  private

  def filter_by_accession(scope, raw)
    return scope unless raw.is_a?(String)

    value = raw.strip[0, MAX_ACCESSION_LENGTH]
    return scope if value.blank?

    scope.where(<<~SQL.squish, pattern: "#{ActiveRecord::Base.sanitize_sql_like(value)}%")
      EXISTS (SELECT 1 FROM projects   WHERE projects.submission_id   = submission_requests.submission_id AND projects.accession   ILIKE :pattern) OR
      EXISTS (SELECT 1 FROM samples    WHERE samples.submission_id    = submission_requests.submission_id AND samples.accession    ILIKE :pattern) OR
      EXISTS (SELECT 1 FROM entries WHERE entries.submission_id = submission_requests.submission_id AND entries.number    ILIKE :pattern)
    SQL
  end
end
