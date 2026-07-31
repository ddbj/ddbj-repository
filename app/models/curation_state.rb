# Everything the curator workbench needs to answer "where is this request,
# and what is the next move" — in one place, so the summary bar, the
# progress stepper, the next-action banner and the curation rail all agree.
#
# The curation rows behind a request differ per database (BP has one
# Project, BS has N Samples, ST.26 has neither), and a BS submission can
# carry 100K of them. Every derived value here is therefore an aggregate
# query, never a `map` over loaded rows.
class CurationState
  # The submitter-legible pipeline. Deliberately shorter than either enum
  # it is derived from: `SubmissionRequest.status` describes the ingest
  # machinery and `Lifecycleable::STATUSES` has nine curation states, and
  # neither answers "how far along is this".
  STEPS = {
    submitted:        'Submitted',
    validated:        'Validated',
    applied:          'Applied',
    curating:         'Curating',
    accession_issued: 'Accession issued',
    public:           'Public'
  }.freeze

  STEP_KEYS = STEPS.keys.freeze

  # Terminal curation states that take a request off the pipeline
  # altogether — showing a half-lit progress bar for a withdrawn record
  # would suggest work is still pending.
  CLOSED_STATUSES = %w[withdrawn canceled permanently_suppressed].freeze

  NextAction = Data.define(:title, :detail, :label)

  # The row aggregates a list screen needs, for a whole page at once. A
  # list asks every row the same "where is this" question, and answering
  # it one CurationState at a time is three aggregate queries per row —
  # so `batch` asks once per model and hands each state its own slice.
  RowSummary = Data.define(:count, :statuses, :accessioned_count)

  EMPTY_ROW_SUMMARY = RowSummary.new(count: 0, statuses: [], accessioned_count: 0)

  def self.batch(requests)
    summaries = row_summaries(requests.filter_map(&:submission))

    requests.to_h {|request|
      summary = request.submission && summaries.fetch(request.submission.id, EMPTY_ROW_SUMMARY)

      [request.id, new(request, row_summary: summary)]
    }
  end

  # {submission_id => RowSummary} over the BP Projects and BS Samples of
  # the given submissions — one grouped query per model. Submissions with
  # no rows are absent, which `batch` reads as EMPTY_ROW_SUMMARY.
  def self.row_summaries(submissions)
    names = Lifecycleable::STATUSES.invert

    [[Project, submissions.select(&:bioproject_db?)], [Sample, submissions.select(&:biosample_db?)]]
      .flat_map {|model, subs|
        next [] if subs.empty?

        model
          .where(submission_id: subs.map(&:id))
          .group(:submission_id)
          .pluck(:submission_id,
                 Arel.sql('COUNT(*) AS row_count'),
                 Arel.sql('ARRAY_AGG(DISTINCT status) AS statuses'),
                 Arel.sql('COUNT(accession) AS accessioned_count'))
      }
      # ARRAY_AGG bypasses the enum's type cast, so the statuses come back
      # as the raw integers the column stores; the rest of this class
      # compares them by name.
      .to_h {|sid, count, statuses, accessioned_count|
        [sid, RowSummary.new(count:, statuses: statuses.compact.map { names.fetch(it, it) }, accessioned_count:)]
      }
  end

  def initialize(request, row_summary: nil)
    @request     = request
    @submission  = request.submission
    @row_summary = row_summary
  end

  attr_reader :request, :submission

  def db = request.db

  # --- curation rows -------------------------------------------------

  # `nil` for a request that has not been applied yet, and for ST.26.
  def rows = @rows ||= submission&.curation_rows

  def row_count = @row_count ||= @row_summary&.count || rows&.count.to_i

  def curated? = row_count.positive?

  def row_noun(count = row_count)
    return 'record' unless submission

    submission.curation_row_noun.pluralize(count)
  end

  def statuses = @statuses ||= @row_summary&.statuses || (rows ? rows.distinct.pluck(:status).compact : [])

  def uniform_status = statuses.size == 1 ? statuses.first : nil

  def status_label
    return '—' unless curated?

    uniform_status&.tr('_', ' ') || "Mixed (#{statuses.size})"
  end

  # Assignment hangs off the request, not the rows, so there is nothing to
  # aggregate and no "Mixed (3)" to display — and it reads the same before
  # Apply, when there are no rows at all.
  def assignee = request.assignee

  def assignee_label = assignee&.uid || 'Unassigned'

  def assigned_to?(user) = request.assignee_id == user.id

  def accessioned_count
    @accessioned_count ||= @row_summary&.accessioned_count || (rows ? rows.where.not(accession: nil).count : 0)
  end

  def first_accession
    @first_accession ||= rows && rows.where.not(accession: nil).minimum(:accession)
  end

  def issuable_count = @issuable_count ||= rows ? AccessionIssue.issuable(rows).count : 0

  def issuable? = issuable_count.positive?

  # Label for the issuance button. Deliberately independent of
  # `next_action`: what to *tell* the curator is a priority question, but
  # what they are *allowed to do* is not. Gating the button on next_action
  # meant an unread message hid the only PRJDB button a BP request has.
  # Nil while an issuance is in flight, so the button is not offered a
  # second time before the first has committed — a second press would
  # allocate a second set of numbers, and SAMD cannot be handed back.
  # `defined?` rather than `||=`: the answer is usually false, and `||=`
  # re-runs the EXISTS on every call — the workbench asks twice per render.
  def issuing?
    return @issuing if defined?(@issuing)

    @issuing = submission.present? && AccessionIssuance.in_flight.where(submission_id: submission.id).exists?
  end

  def issue_label
    return nil if issuing?
    return nil unless issuable?

    "Issue #{accession_prefix} for #{ActiveSupport::NumberHelper.number_to_delimited(issuable_count)} #{row_noun(issuable_count)}"
  end

  # Only BP projects the record's hold date onto a filterable column
  # (Submission#sync_hold_date!). BS has nowhere to put it, and D-way
  # never used a BS hold date — so this is nil there rather than paying
  # for a chain replay to find out.
  def hold_date
    return nil unless submission&.bioproject_db?

    submission.project&.hold_date
  end

  # --- validation ----------------------------------------------------

  def validation = @validation ||= request.validation_with_validity

  def validity = validation&.validity

  # --- progress ------------------------------------------------------

  def failed? = request.status.in?(%w[validation_failed application_failed])

  # Withdrawn / canceled / permanently suppressed: the record has left the
  # pipeline, so the step it stopped on is where it ended, not where work
  # is in progress. Without this a withdrawn BP reads as "Curating" in
  # amber and the submitter is told a curator is reviewing it.
  def closed? = curated? && (statuses - CLOSED_STATUSES).empty?

  # Index into STEPS of the furthest point this request has reached.
  def current_step_index
    @current_step_index ||=
      if curated? && statuses.all? { it == 'public' }             then STEP_KEYS.index(:public)
      elsif curated? && accessioned_count == row_count            then STEP_KEYS.index(:accession_issued)
      elsif curated?                                              then STEP_KEYS.index(:curating)
      elsif submission                                            then STEP_KEYS.index(:applied)
      elsif validity == 'valid'                                   then STEP_KEYS.index(:validated)
      else                                                             STEP_KEYS.index(:submitted)
      end
  end

  # :done for steps already passed, :current for where it sits now,
  # :failed when the pipeline stopped there, :closed when the record left
  # the pipeline altogether, :todo for the rest.
  def step_state(step)
    index = STEP_KEYS.index(step) or raise ArgumentError, "unknown step #{step.inspect}"

    return :failed  if failed? && index == current_step_index + 1
    return :done    if index < current_step_index
    return :closed  if closed? && index == current_step_index
    return :current if index == current_step_index

    :todo
  end

  # --- next action ---------------------------------------------------

  def unread_message_count
    @unread_message_count ||= request.messages.submitter_role.unread.count
  end

  # The single most useful thing a curator could do right now, or nil when
  # the request is not waiting on us. Ordered by who is blocked: a broken
  # pipeline first, then a submitter waiting for a reply, then issuance.
  def next_action
    if failed?
      NextAction.new(
        title:  "#{request.status.tr('_', ' ').capitalize} — the submitter cannot move this forward",
        detail: request.error_message.presence || 'See the validation report for the failing entries.',
        label:  nil
      )
    elsif unread_message_count.positive?
      NextAction.new(
        title:  'The submitter is waiting for a reply',
        detail: "#{unread_message_count} unread #{'message'.pluralize(unread_message_count)} in the thread.",
        label:  nil
      )
    elsif issuing?
      # Announcing eligibility while a run is in flight put "these are
      # eligible — issuing allocates from the Sequence" directly above a
      # bar that had replaced the button with an Issuing… badge.
      NextAction.new(
        title:  'Accessions are being issued',
        detail: 'A run is in flight. The button is gone until it commits, because a second ' \
                'press would allocate a second set of numbers.',
        label:  nil
      )
    elsif issuable?
      NextAction.new(
        title:  "#{ActiveSupport::NumberHelper.number_to_delimited(issuable_count)} #{row_noun(issuable_count)} " \
                "#{issuable_count == 1 ? 'is' : 'are'} eligible for accession issuance",
        detail: "No accession yet and status is #{AccessionIssue::ISSUABLE_FROM.join(' or ')}. " \
                'Issuing allocates from the Sequence, stamps the rows, appends the accession ' \
                'to the record as a patch, and emails the submitter once.',
        label:  issue_label
      )
    end
  end

  def accession_prefix
    submission&.bioproject_db? ? 'PRJDB' : 'SAMD'
  end
end
