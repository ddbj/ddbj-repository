# Allocate one or more accessions from the project Sequence and stamp them
# onto the target rows (BP Project / BS Samples) plus the patch chain. One
# call per submission — for BS we batch all un-accessioned samples in a
# single Sequence.allocate! so the sequence advances exactly N times for
# N samples, not 2N.
#
# Transaction shape:
#   - Sequence allocation + typed column stamp + chain append all happen
#     inside `Submission.transaction`. A failure anywhere rolls back; the
#     Sequence row's `next` rewinds with the rest, so no accession is
#     burned without being persisted.
#   - The mailer is enqueued AFTER `commit` via `transaction do ... end`
#     return value — we don't want to deliver a "your accession is X"
#     mail if the transaction rolls back.
#   - The status transition to `:accession_issued` is part of the same
#     transaction (idempotent: already-issued rows aren't accepted by
#     `call`'s pre-check).
#
# Refuses to operate when:
#   - submission already has all-accessioned rows (BS)
#   - the BP project already has an accession
#   - status is not in {curating, submission_accepted}
#
# Returns a Result with the list of newly-issued accessions, or raises
# AccessionIssue::Refused with a human-readable reason.
class AccessionIssue
  class Refused < StandardError; end

  Result = Data.define(:submission, :accessions)

  ISSUABLE_FROM = %w[submission_accepted curating].freeze

  def self.call(submission:, actor:, samples: nil)
    new(submission:, actor:, samples:).call
  end

  # The refusal rules as a predicate, so the admin UI offers the button
  # only where it would succeed instead of re-deriving the rule and
  # drifting from it. Takes a Project or a Sample — both carry
  # `accession` + a Lifecycleable `status`.
  def self.issuable?(row)
    row.accession.blank? && ISSUABLE_FROM.include?(row.status)
  end

  # Relation form of `issuable?` for counting a submission's samples.
  def self.issuable(relation)
    relation.where(accession: nil, status: ISSUABLE_FROM)
  end

  # `samples` narrows BS issuance to a subset — the rows a curator picked
  # or filtered to on the Samples screen. nil means "every sample in the
  # submission", which is what the cross-submission bulk action wants.
  # Ignored for BP, which has exactly one Project either way.
  def initialize(submission:, actor:, samples: nil)
    @submission = submission
    @actor      = actor
    @samples    = samples
  end

  def call
    case @submission.db
    when 'bioproject' then issue_bp
    when 'biosample'  then issue_bs
    else
      raise Refused, "Accession issuance not supported for db=#{@submission.db.inspect}"
    end
  end

  private

  def issue_bp
    project = @submission.project or raise Refused, 'Submission has no Project row.'

    raise Refused, "Project already has accession #{project.accession}." if project.accession.present?
    raise Refused, "Project status #{project.status} is not issuable." unless ISSUABLE_FROM.include?(project.status)

    accession = Submission.transaction do
      acc = Sequence.allocate!(:bp, 1).first

      project.update!(accession: acc, status: :accession_issued)
      invalidate_cache!(@submission)
      record_event(1, 'PRJDB')

      acc
    end

    enqueue_mail(@submission, [accession])

    Result.new(submission: @submission, accessions: [accession])
  end

  def issue_bs
    targets = self.class.issuable(@samples || @submission.samples).order(:id).to_a

    raise Refused, 'No samples are eligible for accession issuance (all already issued or wrong status).' if targets.empty?

    accessions = Submission.transaction do
      acc_list = Sequence.allocate!(:bs, targets.size)

      targets.zip(acc_list).each do |sample, acc|
        sample.update!(accession: acc, status: :accession_issued)
      end
      invalidate_cache!(@submission)
      record_event(targets.size, 'SAMD')

      acc_list
    end

    enqueue_mail(@submission, accessions)

    Result.new(submission: @submission, accessions:)
  end

  # `/**/accession` is registered as a volatile path in array-modes.yml
  # so `Canonicalizer.diff` strips it from BOTH sides — accession-only
  # edits produce an empty patch and don't generate a SubmissionUpdate
  # entry. The canonical record for accession is the typed column
  # (Project.accession / Sample.accession), not the materialised_record;
  # we just have to null the cache stamp so the next read recomputes
  # from the chain + the current typed-column value. The orphaned blob
  # is displaced on the next prime_cache! (read-side cache fill or
  # importer re-run).
  #
  # Goes through `update_all` to skip the model's update callbacks
  # (we don't want a recursive cache write).
  # Accession is a record field that produces no patch: `/**/accession` is
  # registered volatile, so `Canonicalizer.diff` strips it from both sides
  # and the chain never sees the change. Without an event, issuance would
  # be invisible in the history even though it is the most consequential
  # thing a curator does. Written inside the transaction so a rollback
  # un-records it too.
  def record_event(count, prefix)
    CurationEvent.record!(
      submission: @submission,
      actor:      @actor,
      action:     :accession_issued,
      row_count:  count,
      prefix:     prefix
    )
  end

  def invalidate_cache!(submission)
    Submission.where(id: submission.id).update_all(cached_at_update_id: nil)
  end

  def enqueue_mail(submission, accessions)
    AccessionMailer.with(submission:, accessions:).issued.deliver_later
  end
end
