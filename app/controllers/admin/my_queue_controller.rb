module Admin
  # The curator's landing screen: everything waiting on a curator, split by
  # whether they own it, are involved in it, or nobody has it.
  #
  # Not tabs. A queue's job is to be worked through, and hiding two thirds
  # of it makes "what is left today" something you assemble by clicking
  # rather than something you read. Each section carries the rule that put
  # a request in it, so the meaning is on the screen instead of in a
  # remembered filter.
  class MyQueueController < ApplicationController
    # A section that runs long is a signal in itself, and rendering 400
    # rows helps nobody — the tail becomes a link into the ledger.
    PER_SECTION = 25

    Listing = Data.define(:section, :rows, :sets, :count, :overflow)

    def show
      @sections = MyQueue.new(current_user).sections.map { present(it) }
      @total    = @sections.sum(&:count)

      # Everything the set rows on this page print, asked once for the
      # page rather than once per row.
      sets = @sections.flat_map(&:sets)
      ids  = sets.map(&:id)

      @set_unread    = SubmissionSet.curator_unread_counts(current_user, ids)
      @set_counts    = SubmissionSet.counts_for(ids)
      @waiting_since = SubmissionSet.waiting_since(ids)
      @set_assignees = SubmissionSet.assignee_counts(ids)
      @assignee_uids = assignee_uids(@set_assignees)
    end

    private

    # One lookup for every name any of the rows will print.
    def assignee_uids(counts)
      ids = counts.values.flat_map(&:keys).compact.uniq

      User.where(id: ids).pluck(:id, :uid).to_h
    end

    # Both axes, each capped, so one long side cannot crowd the other out
    # of the page. The overflow line names what is left of the pair.
    def present(section)
      count    = section.count
      requests = section.requests.limit(PER_SECTION).to_a
      sets     = section.set_conversations.limit(PER_SECTION).to_a

      Listing.new(
        section:,
        rows:     rows_for(requests),
        sets:,
        count:,
        overflow: [count - requests.size - sets.size, 0].max
      )
    end

    # Both per-row facts for the whole section at once. Two grouped
    # queries beat a query per row on the one page every curator opens
    # first — and the counts are what the row is *for*, so they cannot be
    # deferred to the detail screen.
    def rows_for(requests)
      unread    = unread_counts(requests)
      issuable  = issuable_counts(requests)

      # One query for the page rather than one per row: while a run is in
      # flight the row must not offer Issue again, and the queue is the
      # easiest of the three places to press twice.
      in_flight = AccessionIssuance.in_flight_submission_ids(requests.filter_map(&:submission_id))

      requests.map {|request|
        pending, total = issuable.fetch(request.submission_id, [0, 0])

        MyQueue::Row.new(request:, unread: unread.fetch(request.id, 0), issuable: pending, total_rows: total,
                         issuing: in_flight.include?(request.submission_id))
      }
    end

    # Per curator, like the sections themselves: a colleague reading the
    # thread must not empty this curator's badge.
    def unread_counts(requests)
      return {} if requests.empty?

      SubmissionMessage
        .submitter_role
        .where(submission_request_id: requests.map(&:id))
        .where(id: MyQueue.unread_message_ids(current_user))
        .group(:submission_request_id)
        .count
    end

    # "12 of 620 samples to issue" — four grouped queries for the whole
    # section rather than two per row. {submission_id => [pending, total]}.
    def issuable_counts(requests)
      ids = requests.filter_map(&:submission_id)
      return {} if ids.empty?

      pending = tally(ids) { AccessionIssue.issuable(it) }
      total   = tally(ids, &:itself)

      ids.index_with { [pending[it].to_i, total[it].to_i] }
    end

    def tally(ids)
      [Project.where(submission_id: ids), Sample.where(submission_id: ids)]
        .map { yield(it).group(:submission_id).count }
        .reduce {|a, b| a.merge(b) {|_, x, y| x + y } }
    end
  end
end
