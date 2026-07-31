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
#
#     The cost of that guarantee: `Sequence.allocate!` takes a row lock
#     that only releases when this outer transaction commits, and since
#     ddbj-canon/v2 the chain append inside it is a full replay plus two
#     canonicalisation passes plus a blob upload. On a 100K-sample BS
#     record that is tens of seconds.
#
#     Committing the allocation on its own would bound the lock and burn
#     an accession number every time the stamp afterwards failed, which
#     is not a trade to make with a published identifier space. So the
#     lock stays and the wait went somewhere nobody is watching it:
#     issuance runs in IssueAccessionsJob, and this is never called from
#     a request.
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
# one of two errors that mean opposite things — see Refused and
# ChainBroken below. A caller that rescues only Refused will crash on a
# corrupt chain, which is the mistake this contract most invites.
class AccessionIssue
  # A rule declined. Reaches the curator as "Skipped", with the reason.
  class Refused < StandardError; end

  # Nothing declined — the submission is broken. Kept apart from Refused
  # because they are different sentences to whoever reads the run page:
  # "this was not eligible" is an answer, "this cannot be replayed" is a
  # defect that somebody has to fix, and grouping them meant a corrupt
  # chain sat in a grey Skipped badge indefinitely with nobody told.
  #
  # Not rescued by the job, so it lands as `failed` and is reported.
  class ChainBroken < StandardError; end

  # `mail_error` is set when the accessions were committed but the
  # notification could not be enqueued. It is not an alternative to
  # `accessions` — the numbers exist either way, and a record that
  # forgets them because the mailer hiccupped is the worse failure.
  Result = Data.define(:submission, :accessions, :mail_error)

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

      update = stamp_record! {|record| (record['project'] ||= {})['accession'] = acc }
      record_event([acc], 'PRJDB', update)

      acc
    end

    Result.new(submission: @submission, accessions: [accession],
               mail_error: enqueue_mail(@submission, [accession]))
  end

  def issue_bs
    targets = self.class.issuable(@samples || @submission.samples).order(:id).to_a

    raise Refused, 'No samples are eligible for accession issuance (all already issued or wrong status).' if targets.empty?

    accessions = Submission.transaction do
      acc_list = Sequence.allocate!(:bs, targets.size)

      targets.zip(acc_list).each do |sample, acc|
        sample.update!(accession: acc, status: :accession_issued)
      end

      # `samples` is a keyed array on `alias` (== sample_name), which is
      # curator input and stable; a sample the record does not carry is
      # skipped rather than invented.
      update = stamp_record! {|record|
        by_alias = Array(record['samples']).index_by { it['alias'] }

        targets.zip(acc_list).each do |sample, acc|
          by_alias[sample.sample_name]&.[]=('accession', acc)
        end
      }

      record_event(acc_list, 'SAMD', update)

      acc_list
    end

    Result.new(submission: @submission, accessions:,
               mail_error: enqueue_mail(@submission, accessions))
  end

  # Write the freshly-issued accessions into the record as a patch.
  #
  # Accession is ordinary record content (canonical-json.md §4.4, v2), so
  # issuance appends a chain entry like any other edit. Under v1 it was a
  # volatile path stripped from both sides of every diff, which meant the
  # single most consequential curator action produced an empty patch and
  # the stored record could disagree with the typed column indefinitely.
  #
  # Returns the SubmissionUpdate, or nil when there is nothing to patch —
  # a submission with no chain yet has nowhere to put it, and the typed
  # column still carries it. Appending also nils the cache stamp via
  # SubmissionUpdate#after_create, so no separate invalidation is needed.
  # The rescue wraps the append too, not just the read. `materialised_
  # record` can be served from the cache while the chain behind it is
  # unreplayable — the importers create exactly that state on purpose
  # (`safe_prior_materialised` swallows the failure, then re-primes the
  # cache) — and `append_update!` replays from scratch.
  #
  # It used to come back as Refused, because issuance ran inline over a
  # loop of submissions and a raise would have abandoned the rest with
  # accessions already committed. Each submission is now its own job and
  # its own transaction, so a raise costs only this one — and calling a
  # broken chain a refusal told the curator the submission was ineligible
  # when what it actually needs is somebody to repair it.
  #
  # Either way the raise leaves the transaction, so nothing is burned.
  def stamp_record!
    record = @submission.materialised_record
    return nil if record.nil?

    updated = record.deep_dup
    yield updated

    @submission.append_update!(updated, actor: @actor, source: :manual)
  rescue Submission::MaterialisationFailed => e
    raise ChainBroken, "Cannot record the accession: the patch chain is unreadable (#{e.message})."
  end

  # The chain entry above says "the record changed"; this says what the
  # change was, in words, and points at that entry so the activity feed
  # shows one line rather than two. Status / assignee events carry no
  # update because they are not record content at all — see CurationEvent.
  # The range travels with the event rather than being re-derived: the
  # feed reads this months later, by which time the rows it came from may
  # have been suppressed, renumbered upstream, or split across
  # submissions. What was issued that day does not change afterwards.
  def record_event(accessions, prefix, update)
    CurationEvent.record!(
      submission:        @submission,
      actor:             @actor,
      action:            :accession_issued,
      row_count:         accessions.size,
      submission_update: update,
      prefix:            prefix,
      range:             AccessionRange.format(accessions)
    )
  end

  # Runs after the transaction has committed, so a failure here cannot
  # take the accessions back — and must not take the *record* of them
  # back either. Returns the reason instead of raising, so the caller
  # writes down what was issued and what did not go out.
  def enqueue_mail(submission, accessions)
    AccessionMailer.with(submission:, accessions:).issued.deliver_later

    nil
  rescue StandardError => e
    Rails.error.report(e, handled: true, source: 'accession_issue.mail')

    "#{e.class}: #{e.message}"
  end
end
