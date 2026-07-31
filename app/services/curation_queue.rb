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
  # The pipeline stopped on OUR side: `application_failed` errored while
  # applying, `waiting_application` was enqueued and never ran. Neither is
  # retryable from the submitter's screen — the web client only offers
  # Apply while the status is `ready_to_apply` — so if a curator does not
  # look, nobody does.
  STALLED_STATUSES = %w[waiting_application application_failed].freeze

  Bucket = Data.define(:key, :title, :description, :scope) do
    # `.count` on a bucket is a badge query — drop the ordering so
    # PostgreSQL doesn't sort rows it is only going to count.
    def count = scope.reorder(nil).count

    def requests = scope.includes(:user, submission: [{project: :assignee}, :accessions])
  end

  def self.buckets
    [
      Bucket.new(
        key:         :stalled,
        title:       'Stuck in our pipeline',
        description: 'Apply errored, or was enqueued and never ran. The submitter has no retry for either.',
        scope:       base.where(status: STALLED_STATUSES)
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
