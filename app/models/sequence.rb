class Sequence < ApplicationRecord
  def self.claim(scope, count: 1)
    upsert({scope:, next: count}, **{
      unique_by:    :scope,
      on_duplicate: Arel.sql("next = next + #{count}"),
      returning:    Arel.sql("next - #{count} + 1 AS start")
    }).pick('start')
  end
end
