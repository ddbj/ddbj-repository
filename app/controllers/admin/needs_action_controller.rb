module Admin
  # The admin landing screen: everything a curator still owes somebody,
  # every bucket at once.
  #
  # Not tabs. A queue's job is to be worked through, and hiding three
  # quarters of it makes "what is left today" something you assemble by
  # clicking rather than something you read. Each bucket carries the rule
  # that put a request in it, so the meaning of the queue is on the screen
  # instead of in a remembered filter combination.
  class NeedsActionController < ApplicationController
    # A bucket that runs long is a signal in itself, and rendering 400 rows
    # helps nobody — the tail becomes a link into the ledger.
    PER_BUCKET = 25

    Listing = Data.define(:bucket, :requests, :count, :overflow)

    def show
      @mine    = params[:mine].present?
      @buckets = CurationQueue.buckets.map { present(it) }
      @total   = scoped(CurationQueue.scope).reorder(nil).count

      # Per-row detail, batched across the whole page rather than derived
      # per request: the landing screen is the one page every curator loads
      # first, and it must not cost a query per row to say what it says.
      @excerpts = last_submitter_messages
      @issuable = issuable_counts
    end

    private

    def present(bucket)
      count = scoped(bucket.scope).reorder(nil).count

      Listing.new(
        bucket:   bucket,
        requests: scoped(bucket.requests).limit(PER_BUCKET).to_a,
        count:    count,
        overflow: [count - PER_BUCKET, 0].max
      )
    end

    # "Mine only" filters the same queue rather than opening a different
    # screen, so a curator can look up from their own work and back without
    # losing their place. My queue stays in the nav for people who live there.
    def scoped(relation)
      @mine ? relation.curated_by(current_user) : relation
    end

    def listed(action)
      @buckets.find { it.bucket.action == action }&.requests.to_a
    end

    # What the submitter actually said, so the row is worth reading before
    # opening the thread.
    def last_submitter_messages
      ids = listed(:reply).map(&:id)
      return {} if ids.empty?

      SubmissionMessage
        .submitter_role.unread.where(submission_request_id: ids)
        .order(:created_at)
        .index_by(&:submission_request_id)
    end

    # "18 of 1,842 samples pending" — four grouped queries for the whole
    # page rather than two per row. Returns {submission_id => [pending, total]}.
    def issuable_counts
      ids = listed(:issue).filter_map(&:submission_id)
      return {} if ids.empty?

      pending = tally(Project.where(submission_id: ids), Sample.where(submission_id: ids)) { AccessionIssue.issuable(it) }
      total   = tally(Project.where(submission_id: ids), Sample.where(submission_id: ids), &:itself)

      ids.index_with { [pending[it].to_i, total[it].to_i] }
    end

    def tally(*relations)
      relations.map { yield(it).group(:submission_id).count }.reduce {|a, b| a.merge(b) {|_, x, y| x + y } }
    end
  end
end
