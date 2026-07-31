# Everything waiting on a curator.
#
# Strictly that: a request whose next move belongs to the submitter is not
# in here, however long it has been sitting. `ready_to_apply` means
# validation passed and the submitter can press Apply; `validation_failed`
# means their file needs fixing. Both already show as "Action needed" on
# the submitter's own screen, and putting them in a curator's red queue
# would split one responsibility across two people, which usually means
# neither takes it.
#
# The admin IA puts business tasks — not database types — at the first
# level, so "Needs action" is the landing screen and its nav badge has to
# be cheap enough to compute on every page render. Each bucket is a plain
# `SubmissionRequest.where(...)` with no joins or includes so the buckets
# can be OR-ed together (`.or` refuses structurally different relations)
# into one scope for the badge, and decorated with `includes` only at the
# point a bucket is actually rendered as a table.
class CurationQueue
  # Machine states. A request passes through them in milliseconds, so their
  # presence says nothing; only their persistence does. Past the grace
  # period they mean a background job should have finished by now — which
  # is nobody's fault but ours, and nobody else is watching for it.
  STUCK_STATUSES = %w[waiting_validation validating waiting_application applying].freeze

  # Long enough that a healthy queue never shows up here, short enough that
  # a dead job is noticed the same working day.
  STUCK_GRACE = 15.minutes

  # The apply step errored. Unlike a validation failure — which the
  # submitter fixes and resubmits — there is no retry on their screen.
  FAILED_STATUSES = %w[application_failed].freeze

  # How each bucket says "why this is here" and what the row offers to do
  # about it. `action` is rendered by admin/needs_action/_row.
  Bucket = Data.define(:key, :title, :criterion, :action, :scope) do
    # `.count` on a bucket is a badge query — drop the ordering so
    # PostgreSQL doesn't sort rows it is only going to count.
    def count = scope.reorder(nil).count

    # Oldest first: a queue is a working order, not a newsfeed.
    def requests
      scope.reorder(updated_at: :asc).includes(:user, submission: [{project: :assignee}, :accessions])
    end
  end

  def self.buckets
    [
      Bucket.new(
        key:       :stuck,
        title:     'Stuck in the pipeline',
        criterion: 'A background job should have finished by now — nobody is waiting on the submitter.',
        action:    :check_job,
        scope:     base.where(status: FAILED_STATUSES)
                       .or(base.where(status: STUCK_STATUSES).where(updated_at: ..STUCK_GRACE.ago))
      ),
      Bucket.new(
        key:       :unread_messages,
        title:     'Unread submitter messages',
        criterion: 'The submitter replied and no curator has opened the thread since.',
        action:    :reply,
        scope:     base.where(id: SubmissionMessage.submitter_role.unread.select(:submission_request_id))
      ),
      Bucket.new(
        key:       :awaiting_accession,
        title:     'Ready for accession issuance',
        criterion: "Curation rows with no accession, in #{AccessionIssue::ISSUABLE_FROM.join(' or ')} status.",
        action:    :issue,
        scope:     base.where(<<~SQL.squish, sids: issuable_status_ids)
          EXISTS (SELECT 1 FROM projects WHERE projects.submission_id = submission_requests.submission_id AND projects.accession IS NULL AND projects.status IN (:sids)) OR
          EXISTS (SELECT 1 FROM samples  WHERE samples.submission_id  = submission_requests.submission_id AND samples.accession  IS NULL AND samples.status  IN (:sids))
        SQL
      )
    ]
  end

  # Every request in any bucket, de-duplicated — a request can sit in more
  # than one (an unread message on a submission that is also awaiting an
  # accession). Backs the nav badge, which must not double-count.
  def self.scope
    buckets.map(&:scope).reduce(:or)
  end

  def self.count = scope.reorder(nil).count

  def self.base = SubmissionRequest.all

  def self.issuable_status_ids
    AccessionIssue::ISSUABLE_FROM.map { Lifecycleable::STATUSES.fetch(it) }
  end

  private_class_method :base, :issuable_status_ids
end
