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

  def initialize(request)
    @request    = request
    @submission = request.submission
  end

  attr_reader :request, :submission

  def db = request.db

  # --- curation rows -------------------------------------------------

  # `nil` for a request that has not been applied yet, and for ST.26.
  def rows = @rows ||= submission&.curation_rows

  def row_count = @row_count ||= rows&.count.to_i

  def curated? = row_count.positive?

  def row_noun(count = row_count)
    return 'record' unless submission

    submission.curation_row_noun.pluralize(count)
  end

  def statuses = @statuses ||= rows ? rows.distinct.pluck(:status).compact : []

  def uniform_status = statuses.size == 1 ? statuses.first : nil

  def status_label
    return '—' unless curated?

    uniform_status&.tr('_', ' ') || "Mixed (#{statuses.size})"
  end

  def assignee_ids = @assignee_ids ||= rows ? rows.distinct.pluck(:assignee_id) : []

  def uniform_assignee_id = assignee_ids.size == 1 ? assignee_ids.first : nil

  def assignee
    @assignee ||= uniform_assignee_id && User.find_by(id: uniform_assignee_id)
  end

  def assignee_label
    return '—' unless curated?
    return "Mixed (#{assignee_ids.size})" if assignee_ids.size > 1

    assignee&.uid || 'Unassigned'
  end

  def assigned_to?(user) = assignee_ids == [user.id]

  def accessioned_count = @accessioned_count ||= rows ? rows.where.not(accession: nil).count : 0

  def first_accession
    @first_accession ||= rows && rows.where.not(accession: nil).minimum(:accession)
  end

  def issuable_count = @issuable_count ||= rows ? AccessionIssue.issuable(rows).count : 0

  def issuable? = issuable_count.positive?

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
  # :failed when the pipeline stopped there, :todo for the rest.
  def step_state(step)
    index = STEP_KEYS.index(step) or raise ArgumentError, "unknown step #{step.inspect}"

    return :failed  if failed? && index == current_step_index + 1
    return :done    if index < current_step_index
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
    elsif issuable?
      NextAction.new(
        title:  "#{ActiveSupport::NumberHelper.number_to_delimited(issuable_count)} #{row_noun(issuable_count)} " \
                "#{issuable_count == 1 ? 'is' : 'are'} eligible for accession issuance",
        detail: "No accession yet and status is #{AccessionIssue::ISSUABLE_FROM.join(' or ')}. " \
                'Issuing allocates from the Sequence, stamps the typed column — which is the ' \
                'authoritative one, since the record field is volatile and produces no patch — ' \
                'and emails the submitter once.',
        label:  "Issue #{accession_prefix} for #{ActiveSupport::NumberHelper.number_to_delimited(issuable_count)} #{row_noun(issuable_count)}"
      )
    end
  end

  def accession_prefix
    submission&.bioproject_db? ? 'PRJDB' : 'SAMD'
  end
end
