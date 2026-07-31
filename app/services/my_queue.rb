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
# What is deliberately still absent: a request whose next move belongs to
# the submitter. `ready_to_apply` means they can press Apply,
# `validation_failed` means their file needs fixing. Both already say
# "Action needed" on the submitter's own screen, and putting them in a
# curator's queue too would split one responsibility across two people,
# which usually means neither takes it.
class MyQueue
  # Why a request is in the queue at all, and what the row offers to do
  # about it. A request can qualify on both counts; `Row#reason` picks the
  # one that blocks somebody else first.
  ISSUABLE_STATUS_IDS = -> { AccessionIssue::ISSUABLE_FROM.map { Lifecycleable::STATUSES.fetch(it) } }

  Section = Data.define(:key, :title, :criterion, :scope) do
    def count = scope.reorder(nil).count

    # Oldest first: a queue is a working order, not a newsfeed.
    def requests
      scope.reorder(updated_at: :asc).includes(:user, :assignee, submission: %i[project accessions])
    end
  end

  # One row as the screen renders it. `unread` and `issuable` are filled
  # from batched queries, never per row — this is the page every curator
  # loads first.
  Row = Data.define(:request, :unread, :issuable, :total_rows) do
    # Ordered by who is blocked: a submitter waiting for an answer comes
    # before an accession nobody is waiting on.
    #
    # Both can be zero. The scope and the per-row counts are separate
    # queries, so another curator opening the thread in between — which
    # marks it read — leaves a row that qualified for neither reason by
    # the time it renders. Saying nothing is right; guessing "issue" and
    # rendering a button for a submission that may not exist is a 500 on
    # the landing page.
    def action
      return :reply if unread.positive?
      return :issue if issuable.positive?

      nil
    end

    def reason
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
        scope:     needing_curator.assigned_to(user)
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
        scope:     needing_curator.involving(user).where('submission_requests.assignee_id IS DISTINCT FROM ?', user.id)
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
  def self.needing_curator
    base = SubmissionRequest.all

    base.where(id: SubmissionMessage.submitter_role.unread.select(:submission_request_id))
        .or(base.where(<<~SQL.squish, sids: ISSUABLE_STATUS_IDS.call))
          EXISTS (SELECT 1 FROM projects WHERE projects.submission_id = submission_requests.submission_id AND projects.accession IS NULL AND projects.status IN (:sids)) OR
          EXISTS (SELECT 1 FROM samples  WHERE samples.submission_id  = submission_requests.submission_id AND samples.accession  IS NULL AND samples.status  IN (:sids))
        SQL
  end

  def needing_curator = self.class.needing_curator
end
