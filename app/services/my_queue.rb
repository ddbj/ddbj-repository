# Everything waiting on a curator, arranged by that curator's relationship
# to it.
#
# This replaces a separate "Needs action" screen. Once the buckets a
# curator could not act on were removed — a background job that died is
# reported to Sentry and listed under /admin/jobs, not something anyone
# reads a queue to discover — the work converged on two things: answer the
# submitter, or issue accessions. Two kinds of work did not need a screen
# of their own alongside "my work"; they needed to BE it.
#
# A status is never a reason to be here. `ready_to_apply` means the
# submitter can press Apply and `validation_failed` means their file
# needs fixing; both already say "Action needed" on their own screen, and
# queueing them for a curator as well would split one responsibility
# across two people, which usually means neither takes it.
#
# An unread message still counts, whatever the status says. Somebody who
# asks a question while their file sits unapplied is waiting on an
# answer, and refusing to queue that would be the same failure from the
# other direction.
class MyQueue
  # Why a request is in the queue at all, and what the row offers to do
  # about it. A request can qualify on both counts; `Row#reason` picks the
  # one that blocks somebody else first.
  ISSUABLE_STATUS_IDS = -> { AccessionIssue::ISSUABLE_FROM.map { Lifecycleable::STATUSES.fetch(it) } }

  Section = Data.define(:key, :title, :criterion, :scope) do
    def count = scope.reorder(nil).count

    # Oldest first: a queue is a working order, not a newsfeed.
    def requests
      scope.reorder(updated_at: :asc).includes(:user, :assignee, submission: %i[project entries])
    end
  end

  # One row as the screen renders it. `unread` and `issuable` are filled
  # from batched queries, never per row — this is the page every curator
  # loads first.
  Row = Data.define(:request, :unread, :issuable, :total_rows, :issuing) do
    # Ordered by who is blocked: a submitter waiting for an answer comes
    # before an accession nobody is waiting on.
    #
    # Both can be zero. The scope and the per-row counts are separate
    # queries, so anything that discharges the request in between — this
    # curator marking the thread read in another tab, an accession being
    # issued — leaves a row that qualified for neither reason by the time
    # it renders. Saying nothing is right; guessing "issue" and rendering
    # a button for a submission that may not exist is a 500 on the
    # landing page.
    def action
      return :reply if unread.positive?
      return :issue if issuable.positive? && !issuing

      nil
    end

    def reason
      return "#{delimited(issuable)} #{noun} being issued" if issuing && unread.zero?

      case action
      when :reply then "#{unread} unread #{'message'.pluralize(unread)}"
      when :issue then "#{delimited(issuable)} of #{delimited(total_rows)} #{noun} to issue"
      end
    end

    private

    def delimited(count) = ActiveSupport::NumberHelper.number_to_delimited(count)

    def noun = request.submission&.curation_row_noun&.pluralize(total_rows) || 'rows'
  end

  def initialize(user)
    @user = user
  end

  attr_reader :user

  # The three are disjoint by construction, so the badge is their sum and
  # no request is worked on twice. A request assigned to somebody else
  # that this curator has never touched is in none of them — which is the
  # point: it is not their queue.
  def sections
    [
      Section.new(
        key:       :assigned,
        title:     'Assigned to me',
        criterion: 'You took these on — assignment only changes when someone changes it.',
        scope:     needing_curator(user).assigned_to(user)
      ),
      # IS DISTINCT FROM, not `!=`: SQL inequality is NULL for an
      # unassigned row, so `where.not(assignee_id: id)` silently drops
      # exactly the requests that are involved-but-unowned — and since
      # `unclaimed` excludes anything with a participant, replying to a
      # submitter made the request vanish from every curator's queue.
      Section.new(
        key:       :involved,
        title:     "I'm involved",
        criterion: 'You replied or edited here — someone else holds the assignment.',
        scope:     needing_curator(user).involving(user).where('submission_requests.assignee_id IS DISTINCT FROM ?', user.id)
      ),
      Section.new(
        key:       :unclaimed,
        title:     'Unclaimed',
        criterion: 'No assignee, nobody has replied — every curator sees this section identically.',
        scope:     needing_curator.unclaimed
      )
    ]
  end

  def count = sections.sum(&:count)

  # Requests with something a curator can actually do. Kept as two plain
  # `where`s so they can be OR-ed (`.or` refuses structurally different
  # relations) and so the nav badge stays one aggregate query.
  #
  # "Something to do" is an unanswered submitter message — one no curator
  # has posted after. A colleague ANSWERING settles it for everyone,
  # because that is the work being done; a colleague merely READING used
  # to settle it too, and no longer does anything at all.
  #
  # Given a curator it narrows further to what they have not put aside
  # themselves, so one of them dismissing a thread does not speak for the
  # others.
  #
  # A request the submitter has closed is nobody's work: they have said
  # they are not taking it further, and a curator asking anything reopens
  # it (see Admin::MessagesController). Without this the queue would go on
  # demanding a reply to an attempt that had been abandoned.
  def self.needing_curator(user = nil)
    base = SubmissionRequest.where(closed_at: nil)

    base.where(id: unread_request_ids(user))
        .or(base.where(<<~SQL.squish, sids: ISSUABLE_STATUS_IDS.call))
          EXISTS (SELECT 1 FROM projects WHERE projects.submission_id = submission_requests.submission_id AND projects.accession IS NULL AND projects.status IN (:sids)) OR
          EXISTS (SELECT 1 FROM samples  WHERE samples.submission_id  = submission_requests.submission_id AND samples.accession  IS NULL AND samples.status  IN (:sids))
        SQL
  end

  # Requests carrying a submitter message this curator has not got to.
  # A subscription with no marker has read nothing, which is why the join
  # is LEFT — a request they follow but have never opened is unread in
  # full.
  def self.unread_request_ids(user) = unread_messages(user).select(:submission_request_id)

  # The rows behind it, for the per-row badge — same rule, asked once.
  def self.unread_message_ids(user) = unread_messages(user).select(:id)

  def self.unread_messages(user)
    return SubmissionMessage.unanswered unless user

    # Bound rather than interpolated. `to_i` would be safe and Brakeman
    # would accept it, but a value spliced into SQL reads the same as a
    # parameter spliced into SQL, and the reader has to know which — see
    # SubmissionRequest::NEEDS_SUBMITTER_ACTION for the same call.
    # Not filtered on `unsubscribed_at`. Where a curator got to and
    # whether they want to hear about it are separate facts: the marker
    # says what they have seen, the subscription decides whether the
    # request reaches them at all (see `involving`). Filtering here as
    # well made the two readers of the same marker disagree — the
    # Messages tab said nothing was unread while the queue went on
    # counting it.
    join = SubmissionMessage.sanitize_sql_array([<<~SQL.squish, user_id: user.id])
      LEFT JOIN submission_request_participants
        ON submission_request_participants.submission_request_id = submission_messages.submission_request_id
       AND submission_request_participants.user_id = :user_id
    SQL

    SubmissionMessage
      .unanswered
      .joins(join)
      .where('submission_request_participants.last_read_at IS NULL OR submission_messages.created_at > submission_request_participants.last_read_at')
  end

  def needing_curator(for_user = nil) = self.class.needing_curator(for_user)
end
