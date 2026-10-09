# Allocate one or more accessions from the project Sequence and stamp them
# onto the target rows (BP Project / BS Samples / DRA's DRASubmission) plus
# the patch chain. One call per submission — for BS we batch all
# un-accessioned samples in a single Sequence.allocate! so the sequence
# advances exactly N times for N samples, not 2N. A DRA submission is
# numbered whole: see `issue_dra`.
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
#   - the BP project or the DRA submission already has an accession
#   - status is not in {curating, submission_accepted}
#   - the DRA submission was imported from D-way, or DRA's numbering has not
#     been taken over from D-way yet (`refusal_for`)
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

  # `mail_status` is what became of the notification, and `mail_error`
  # the reason when it is `failed`. Neither is an alternative to
  # `accessions` — the numbers exist either way, and a record that
  # forgets them because the mailer hiccupped is the worse failure.
  Result = Data.define(:submission, :accessions, :mail_status, :mail_error)

  ISSUABLE_FROM = %w[submission_accepted curating].freeze

  # What each database's issuance allocates — for DRA, the submission's.
  PREFIXES = {
    'bioproject' => 'PRJDB',
    'biosample'  => 'SAMD',
    'dra'        => 'DRA'
  }.freeze

  # The rest of a DRA submission's numbers: one for each object of these
  # lists in its record that has none, of the kind's prefix (whose Sequence
  # scope is the prefix's lower case). Study and sample have none of their
  # own — D-way has issued no DRP or DRS since 2022; they are the BioProject
  # and BioSample the record refers to.
  DRA_OBJECTS = {
    'experiments' => 'DRX',
    'runs'        => 'DRR',
    'analyses'    => 'DRZ'
  }.freeze

  # What each prefix numbers, as the confirmation names it.
  TARGETS = {
    'PRJDB' => 'projects',
    'SAMD'  => 'samples with no accession',
    'DRA'   => 'DRA submissions',
    'DRX'   => 'experiments',
    'DRR'   => 'runs',
    'DRZ'   => 'analyses'
  }.freeze

  # Why each of the others has none here, in the words a curator reads —
  # on the confirmation, as the refusal of a press, and on the run page.
  REFUSALS = {
    'st26' => 'ST.26 accessions are allocated when the file is applied, not issued here.'
  }.freeze

  IMPORTED_DRA = 'DRA submissions imported from D-way are numbered there.'

  # Until it is, D-way issues the same numbers.
  DRA_NOT_TAKEN_OVER = "DRA numbering has not been taken over from D-way yet (rake dra:take_over_numbering), so it would issue D-way's numbers again.".freeze

  def self.dra_scopes = ['DRA', *DRA_OBJECTS.values].map(&:downcase)

  def self.dra_taken_over? = Sequence.where(scope: dra_scopes).where.not(taken_over_after: nil).count == dra_scopes.size

  def self.supported?(submission) = PREFIXES.key?(submission.db)

  # What issuing would allocate, by prefix — the rows that would be
  # numbered, and for DRA the objects of its record with them. Empty where
  # nothing would be, a DRA submission with no record among them, as
  # `issue_dra` refuses one. Reads a DRA submission's record, so raises
  # Submission::MaterialisationFailed where that cannot be read.
  def self.allocation(submission, rows = submission.curation_rows)
    return {} if rows.nil? || refusal_for(submission)

    count = issuable(rows).count

    return count.positive? ? {PREFIXES.fetch(submission.db) => count} : {} unless submission.dra_db?
    return {} if count.zero?

    record = submission.materialised_record or return {}

    {'DRA' => 1, **DRA_OBJECTS.to_h {|list, prefix| [prefix, unnumbered(record, list).size] }}.select { _2.positive? }
  end

  def self.unnumbered(record, list)
    Array(record[list]).select { it.is_a?(Hash) && it['accession'].blank? }
  end

  # Nil for a submission whose accessions are issued here.
  def self.refusal_for(submission)
    return REFUSALS.fetch(submission.db) unless supported?(submission)
    return unless submission.dra_db?
    return IMPORTED_DRA if submission.source_id

    DRA_NOT_TAKEN_OVER unless dra_taken_over?
  end

  def self.call(submission:, actor:, samples: nil, issuance: nil)
    new(submission:, actor:, samples:, issuance:).call
  end

  # The refusal rules as a predicate, so the admin UI offers the button
  # only where it would succeed instead of re-deriving the rule and
  # drifting from it. Takes any curation row — each carries `accession` +
  # a Lifecycleable `status`.
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
  # `issuance` is the row this run reports on. It travels with the mail so
  # the delivery job can settle `mail_status` when it knows the answer —
  # see MailDeliveryJob.
  def initialize(submission:, actor:, samples: nil, issuance: nil)
    @submission = submission
    @actor      = actor
    @samples    = samples
    @issuance   = issuance
  end

  def call
    if (refusal = self.class.refusal_for(@submission))
      raise Refused, refusal
    end

    case @submission.db
    when 'bioproject' then issue_bp
    when 'biosample'  then issue_bs
    when 'dra'        then issue_dra
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

      update = stamp_record! {|record| BioProject.record_project!(record)['accession'] = acc }
      record_event([acc], update)
      conclude! [acc]

      acc
    end

    Result.new(submission: @submission, accessions: [accession], **enqueue_mail([accession]))
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

      record_event(acc_list, update)
      conclude! acc_list, names: acc_list.zip(targets.map(&:sample_name)).to_h

      acc_list
    end

    Result.new(submission: @submission, accessions:, **enqueue_mail(accessions))
  end

  # A DRA submission is numbered whole, as D-way numbers it: one DRA for the
  # submission, and one of its kind's for each experiment, run and analysis
  # of its record that has none — in alias order within a kind, as D-way
  # orders them, which is the order the record is kept in (canonical-json.md:
  # these lists are keyed by alias). The numbers go into the record, the
  # submission's onto its row.
  #
  # One imported from D-way is numbered there; one numbered already is not
  # numbered again, here or by a second press.
  def issue_dra
    row = @submission.dra_submission or raise Refused, 'Submission has no DRA submission row.'

    raise Refused, "DRA submission already has accession #{row.accession}." if row.accession.present?
    raise Refused, "DRA submission status #{row.status} is not issuable." unless ISSUABLE_FROM.include?(row.status)

    # What each number is the submitter's name for: thousands of DRR in a
    # list say nothing without it.
    names = {}

    accessions = Submission.transaction do
      issued = []

      update = stamp_record! {|record|
        dra = Sequence.allocate!(:dra, 1).first

        (record['submission'] ||= {})['accession'] = dra
        issued << dra
        names[dra] = ['submission', record.dig('submission', 'alias')].compact.join(' ')

        DRA_OBJECTS.each do |list, prefix|
          objects = self.class.unnumbered(record, list)

          next if objects.empty?

          Sequence.allocate!(prefix.downcase.to_sym, objects.size).zip(objects).each do |acc, object|
            object['accession'] = acc
            issued << acc
            names[acc] = [list.singularize, object['alias']].compact.join(' ')
          end
        end
      }

      raise Refused, 'Submission has no record to number.' unless update

      row.update!(accession: issued.first, status: :accession_issued)

      record_event(issued, update)
      conclude!(issued, names:)

      issued
    end

    Result.new(submission: @submission, accessions:, **enqueue_mail(accessions))
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
  def record_event(accessions, update)
    CurationEvent.record!(
      submission:        @submission,
      actor:             @actor,
      action:            :accession_issued,
      row_count:         accessions.size,
      submission_update: update,
      # None where the numbers are of several (DRA): the range names each.
      prefix:            (PREFIXES.fetch(@submission.db) unless @submission.dra_db?),
      range:             AccessionRun.label(accessions)
    )
  end

  # In the commit that issues the numbers, so a run stopped after it is not
  # taken for one that issued nothing: run again, it would be refused —
  # every target has its accession — and say so over numbers that exist.
  # The notice to the submitter is in it for the same reason: a run that
  # issued has told them so in the thread, and one that did not has not.
  def conclude!(accessions, names: {})
    @issuance&.update!(status: 'completed', accessions:, finished_at: Time.current)
    @notice = SubmissionNotice.accession_issued!(@submission, accessions, names:)
  end

  # Runs after the transaction has committed, so a failure here cannot
  # take the accessions back — and must not take the *record* of them
  # back either. Returns the outcome instead of raising, so the caller
  # writes down what was issued and what did not go out.
  #
  # The two silent outcomes are settled here rather than left to be
  # guessed from an empty error: a submitter with no address on file gets
  # nothing, and so does one outside the environment's mail allowlist.
  # Both used to reach the run page as "sent". The third — a delivery
  # that fails after its retries — is settled by the delivery job, which
  # is the only place that knows.
  def enqueue_mail(accessions)
    # Whom the mail goes to: the thread's owner, read where the mailer reads it.
    address = @notice.submission_request.user.email

    return {mail_status: 'no_address', mail_error: nil} if address.blank?
    return {mail_status: 'restricted', mail_error: nil} unless MailDomainAllowlistInterceptor.delivers_to?(address)

    # Only what the subject needs: the job row carries its arguments, and
    # the whole list can run to a hundred thousand.
    AccessionMailer.with(notice: @notice, first: accessions.first, count: accessions.size, issuance: @issuance).issued.deliver_later

    # Queued, not sent. `deliver_later` has promised nothing yet — the
    # delivery job settles this either way (MailDeliveryJob#settle).
    {mail_status: 'queued', mail_error: nil}
  rescue StandardError => e
    Rails.error.report(e, handled: true, source: 'accession_issue.mail')

    {mail_status: 'failed', mail_error: "#{e.class}: #{e.message}"}
  end
end
