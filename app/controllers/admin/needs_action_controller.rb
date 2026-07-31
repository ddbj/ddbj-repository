module Admin
  # The admin landing screen: everything a curator still owes somebody,
  # grouped by why it is stuck rather than by which database it lives in.
  #
  # One bucket is expanded at a time (`?bucket=`) so a queue of thousands
  # doesn't render four paginated tables at once; the others show as
  # counted tabs. Defaults to the first non-empty bucket, which makes the
  # landing page open on actual work instead of an empty list.
  class NeedsActionController < ApplicationController
    include RequestListing

    def show
      @buckets = CurationQueue.buckets
      @counts  = @buckets.to_h { [it.key, it.count] }
      @bucket  = pick_bucket

      load_requests(@bucket.requests)
    end

    private

    def pick_bucket
      requested = @buckets.find { it.key.to_s == params[:bucket] }
      return requested if requested

      @buckets.find { @counts.fetch(it.key).positive? } || @buckets.first
    end
  end
end
