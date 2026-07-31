# What is not moving, sliced into buckets.
#
# Mostly that is work a curator owes somebody. `pending_apply` is the
# exception and is included deliberately: `ready_to_apply` waits on the
# submitter, not on us, but a request that sits there for a week is a
# problem somebody has to notice, and nobody else is looking.
#
# The admin IA puts business tasks — not database types — at the first
# level, so "Needs action" is the landing screen and its nav badge has to
# be cheap enough to compute on every page render. Each bucket is a plain
# `SubmissionRequest.where(...)` with no joins or includes so the buckets
# can be OR-ed together (`.or` refuses structurally different relations)
# into one scope for the badge, and decorated with `includes` only at the
# point a bucket is actually rendered as a table.
class CurationQueue
  # Statuses where the pipeline stopped on an error the submitter cannot
  # clear alone, and statuses where the request is waiting for somebody to
  # press Apply. Both are "nothing is moving until a human looks".
  FAILED_STATUSES  = %w[validation_failed application_failed].freeze
  PENDING_STATUSES = %w[ready_to_apply waiting_application].freeze

  Bucket = Data.define(:key, :title, :description, :scope) do
    # `.count` on a bucket is a badge query — drop the ordering so
    # PostgreSQL doesn't sort rows it is only going to count.
    def count = scope.reorder(nil).count

    def requests = scope.includes(:user, submission: [{project: :assignee}, :accessions])
  end

  def self.buckets
    [
      Bucket.new(
        key:         :pending_apply,
        title:       'Not applied yet',
        description: 'Validated and waiting to be applied — no submission exists until somebody presses Apply.',
        scope:       base.where(status: PENDING_STATUSES)
      ),
      Bucket.new(
        key:         :failed,
        title:       'Failed',
        description: 'Validation or application ended in an error. The submitter cannot move these forward on their own.',
        scope:       base.where(status: FAILED_STATUSES)
      ),
      Bucket.new(
        key:         :unread_messages,
        title:       'Unread messages',
        description: 'The submitter has replied and no curator has opened the thread since.',
        scope:       base.where(id: SubmissionMessage.submitter_role.unread.select(:submission_request_id))
      ),
      Bucket.new(
        key:         :awaiting_accession,
        title:       'Awaiting accession',
        description: "Curation rows with no accession that #{AccessionIssue::ISSUABLE_FROM.join(' / ')} status makes issuable.",
        scope:       base.where(<<~SQL.squish, sids: issuable_status_ids)
          EXISTS (SELECT 1 FROM projects WHERE projects.submission_id = submission_requests.submission_id AND projects.accession IS NULL AND projects.status IN (:sids)) OR
          EXISTS (SELECT 1 FROM samples  WHERE samples.submission_id  = submission_requests.submission_id AND samples.accession  IS NULL AND samples.status  IN (:sids))
        SQL
      )
    ]
  end

  # Every request in any bucket, de-duplicated — a request can sit in more
  # than one (an unread message on a submission that is also awaiting an
  # accession). Backs the nav badge and the "everything" fallback list.
  def self.scope
    buckets.map(&:scope).reduce(:or)
  end

  def self.count = scope.reorder(nil).count

  def self.base = SubmissionRequest.order(id: :desc)

  def self.issuable_status_ids
    AccessionIssue::ISSUABLE_FROM.map { Lifecycleable::STATUSES.fetch(it) }
  end

  private_class_method :base, :issuable_status_ids
end
