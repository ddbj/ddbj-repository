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

  def self.call(submission:, actor:)
    new(submission:, actor:).call
  end

  def initialize(submission:, actor:)
    @submission = submission
    @actor      = actor
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

      acc
    end

    enqueue_mail(@submission, [accession])

    Result.new(submission: @submission, accessions: [accession])
  end

  def issue_bs
    targets = @submission.samples
                         .where(accession: nil)
                         .where(status: ISSUABLE_FROM)
                         .order(:id)
                         .to_a

    raise Refused, 'No samples are eligible for accession issuance (all already issued or wrong status).' if targets.empty?

    accessions = Submission.transaction do
      acc_list = Sequence.allocate!(:bs, targets.size)

      targets.zip(acc_list).each do |sample, acc|
        sample.update!(accession: acc, status: :accession_issued)
      end
      invalidate_cache!(@submission)

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
  # we just have to null the cached_materialised_record bytea so the
  # next read recomputes from the chain + the current typed-column
  # value (Importer convention: typed column drives the next re-emit).
  #
  # Goes through `update_all` to skip the model's update callbacks
  # (we don't want a recursive cache write).
  def invalidate_cache!(submission)
    Submission.where(id: submission.id)
              .update_all(cached_materialised_record: nil, cached_at_update_id: nil)
  end

  def enqueue_mail(submission, accessions)
    AccessionMailer.with(submission:, accessions:).issued.deliver_later
  end
end
