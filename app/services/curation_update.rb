# One curator decision, applied across the four places it actually lives.
#
# Status and assignee are typed columns on the curation rows; hold date is
# a field of the v3 record and therefore a patch on the chain; the curator
# comment is a column on the submission and never reaches the record. A
# curator does not think of those as four edits, so they are saved
# together — this is where the fan-out happens.
#
# Leave-as-is is expressed by absence, not by a sentinel: a key missing
# from `params` is untouched. `assignee_id` is the one exception, because
# "no assignee" has to be expressible — `"0"` clears it, matching the
# convention the request list already uses.
class CurationUpdate
  class Refused < StandardError; end

  Result = Data.define(:changes) do
    def any? = changes.any?

    def to_sentence = changes.to_sentence
  end

  UNASSIGNED = '0'

  def initialize(submission:, actor:, params:)
    @submission = submission
    @actor      = actor
    @params     = params
  end

  def call
    rows    = apply_rows            # {'status' => …, 'assignee' => …} — only what actually changed
    comment = apply_curator_comment # true when the column moved
    hold    = apply_hold_date       # rendered fragments; already a patch, so not an event

    record_event(rows, comment)

    Result.new(changes: describe(rows, comment) + hold)
  end

  private

  attr_reader :submission, :actor, :params

  # Status, assignee and the comment never reach the DDBJ Record, so no
  # patch describes them — without an event they would leave nothing but a
  # bumped `updated_at`. The hold date is deliberately absent: it IS record
  # content, so the chain already tells that story.
  def record_event(rows, comment)
    return if rows.empty? && !comment

    CurationEvent.record!(
      submission:,
      actor:,
      action:    :curation_updated,
      row_count: rows.any? ? (@row_count || 0) : 0,
      noun:      submission.curation_row_noun,
      status:    rows['status'],
      assignee:  rows['assignee'],
      curator_comment: comment.presence
    )
  end

  def describe(rows, comment)
    rows.map {|field, value| "#{field}=#{value}" } + (comment ? ['curator comment'] : [])
  end

  # `update_all` (1 SQL) so a 100K-sample submission stays interactive.
  # That bypasses validations and callbacks, so both values are checked
  # here first — the same trade the bulk endpoints already make.
  #
  # The form always posts the current value for a uniform field, so a save
  # that only touched the comment would otherwise rewrite every sample
  # row. Comparing against what is already there keeps the write (and the
  # flash) to what actually changed.
  # Returns the fields that actually moved, keyed for both the flash and
  # the audit event.
  def apply_rows
    return {} if params[:status].blank? && params[:assignee_id].blank?

    rows = submission.curation_rows or raise Refused, 'This submission has no curation rows to update.'

    attrs   = {}
    changed = {}

    if params[:status].present?
      status = params[:status].to_s
      raise Refused, "Unknown status: #{status.inspect}." unless Lifecycleable::STATUSES.key?(status)

      unless rows.distinct.pluck(:status) == [status]
        attrs[:status]     = Lifecycleable::STATUSES.fetch(status)
        changed['status']  = status
      end
    end

    if params[:assignee_id].present?
      assignee_id = resolve_assignee_id(params[:assignee_id].to_s)

      unless rows.distinct.pluck(:assignee_id) == [assignee_id]
        attrs[:assignee_id]  = assignee_id
        changed['assignee']  = assignee_id ? User.find(assignee_id).uid : 'unassigned'
      end
    end

    return {} if attrs.empty?

    attrs[:updated_at] = Time.current
    @row_count = rows.update_all(attrs)

    changed
  end

  def resolve_assignee_id(raw)
    return nil if raw == UNASSIGNED

    assignee = User.find_by(id: raw)
    raise Refused, 'Assignee must be an admin user.' unless assignee&.admin?

    assignee.id
  end

  # `submission.hold_date` is a v3 record field, so it goes through the
  # patch chain — and then onto the projected `projects.hold_date` column,
  # without which DistributionNotifier can never see the edit (a blob
  # patch chain is not filterable in SQL). See Submission#sync_hold_date!.
  def apply_hold_date
    return [] unless params.key?(:hold_date)

    raw       = params[:hold_date].to_s.strip
    hold_date = parse_iso_date(raw) if raw.present?

    raise Refused, 'Hold date must be a valid YYYY-MM-DD date.' if raw.present? && hold_date.nil?

    record = patched_record(hold_date)
    return [] if record.nil?

    update = submission.append_update!(record, actor:, source: :manual)
    submission.sync_hold_date!(record)

    update ? ["hold date=#{hold_date || '—'}"] : []
  end

  # Strict ISO-8601 only — Date.parse would happily turn "May" or "12"
  # into a today-anchored date, silently fabricating a hold value. The
  # anchor rejects month-name / day-only partials before Date.iso8601 runs.
  def parse_iso_date(raw)
    return nil unless raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.iso8601(raw).iso8601
  rescue Date::Error
    nil
  end

  def patched_record(hold_date)
    current = submission.materialised_record
    return nil if current.nil?

    record = current.deep_dup
    block  = record['submission'] ||= {}

    if hold_date
      block['hold_date'] = hold_date
    else
      block.delete('hold_date')
    end

    record.delete('submission') if block.empty?
    record
  end

  # `update_columns` bypasses Submission's `validates :ddbj_record,
  # attached: true, on: :update` — that rule guards user-facing submission
  # flows, not curator-internal typed-column writes. Migration-sourced
  # submissions carry no ddbj_record blob at all.
  def apply_curator_comment
    return false unless params.key?(:curator_comment)

    body = params[:curator_comment].presence
    return false if body == submission.curator_comment

    submission.update_columns(curator_comment: body)

    true
  end
end
