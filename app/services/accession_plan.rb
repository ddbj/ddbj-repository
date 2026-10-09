# What pressing Issue would actually do, worked out before it is pressed.
#
# The confirmation used to be one `turbo_confirm` line asking whether to
# issue "for the selected submissions", which names neither how many
# accessions that is nor which of the selection will be quietly skipped —
# and a skip was only discoverable afterwards, in a flash, by which time
# the mistake had already been made on the others.
#
# Counting is the same predicate the service enforces (`AccessionIssue
# .issuable`), so the dialog cannot promise something the run then
# refuses.
class AccessionPlan
  # One submission's share of it. `issuable` is the rows that would be
  # numbered and `total` what the submission holds — "18 move, the other
  # 1,824 stay" is the sentence a curator needs, and it needs both numbers.
  # `allocation` is what would be allocated, by prefix: a row's number, and
  # for a DRA submission its experiments', runs' and analyses' too.
  Item = Data.define(:submission, :allocation, :issuable, :total, :skip_reason) do
    def skipped? = skip_reason.present?

    def request = submission.request

    # What it is of, where nothing would be allocated too — the dialog's
    # heading names it either way.
    def prefixes = allocation.keys.presence || [AccessionIssue::PREFIXES[submission.db]].compact

    def accession_count = allocation.values.sum
  end

  def self.for(submissions, targeting: {})
    new(submissions, targeting:)
  end

  def initialize(submissions, targeting: {})
    @submissions = Array(submissions)
    @targeting   = targeting
  end

  def items = @items ||= @submissions.map { item_for(it) }

  def issuing = items.reject(&:skipped?)

  def skipped = items.select(&:skipped?)

  # The button's own label. A total is what makes "this is irreversible"
  # concrete — 19 is a different decision from 1.
  def accession_count = issuing.sum(&:accession_count)

  # One mail per submission that issues anything. Named separately
  # because it is the part that leaves the building.
  def mail_count = issuing.size

  def any? = accession_count.positive?

  # Grouped for the dialog's breakdown: "SAMD to samples with no
  # accession — 18", "PRJDB to projects — 1".
  def by_prefix
    issuing.map(&:allocation).reduce({}) { _1.merge(_2) {|_, a, b| a + b } }
  end

  private

  # Already being issued by an earlier press. The row UIs hide their own
  # button while that is true, but a tick on the ledger can still reach
  # one, and the job would refuse it — so the dialog says so first rather
  # than counting numbers that will never be allocated.
  def in_flight = @in_flight ||= AccessionIssuance.in_flight_submission_ids(@submissions.map(&:id))

  def item_for(submission)
    rows = submission.curation_rows

    return Item.new(submission:, allocation: {}, issuable: 0, total: 0,
                    skip_reason: 'has nothing to issue accessions for') if rows.nil?

    if (refusal = AccessionIssue.refusal_for(submission))
      return Item.new(submission:, allocation: {}, issuable: 0, total: rows.count, skip_reason: refusal.chomp('.'))
    end

    if in_flight.include?(submission.id)
      return Item.new(submission:, allocation: {}, issuable: 0, total: rows.count,
                      skip_reason: 'is already issuing — wait for that run to finish')
    end

    scoped = targeted(submission) || rows

    begin
      allocation = AccessionIssue.allocation(submission, scoped)
    rescue Submission::MaterialisationFailed
      return Item.new(submission:, allocation: {}, issuable: 0, total: rows.count, skip_reason: 'has a record that cannot be read')
    end

    Item.new(
      submission:,
      allocation:,
      issuable:    AccessionIssue.issuable(scoped).count,
      total:       rows.count,
      skip_reason: (skip_reason_for(submission, scoped) if allocation.empty?)
    )
  end

  # Says which rule declined, not merely that something did — a curator
  # who picked a released submission by mistake can see that from here
  # and fix the selection rather than the flash afterwards.
  def skip_reason_for(submission, rows)
    # Numbered from its record, which it has none of.
    return 'has no record to number' if submission.dra_db? && submission.materialised_record.nil?

    pending = rows.where(accession: nil)

    # An empty target set is not "all done": a stale ids list from
    # a page rendered before somebody else moved the rows resolves to
    # nothing, and reporting that as already-accessioned is a different
    # claim entirely.
    return 'nothing matched this selection' if rows.empty?
    return 'every row already has an accession' if pending.none?

    # Only the rows that still need one. Listing every status would put
    # `accession_issued` in the reason for rows that are not the obstacle.
    statuses = pending.distinct.pluck(:status)

    "status is #{statuses.map { it.to_s.tr('_', ' ') }.to_sentence} — not " \
      "#{AccessionIssue::ISSUABLE_FROM.map { it.tr('_', ' ') }.join(' or ')}"
  end

  # Only the single-submission dialog carries a targeting; the ledger's
  # bulk is always whole submissions.
  def targeted(submission)
    return nil if @targeting.blank? || !submission.biosample_db?

    AccessionIssuance.new(submission:, targeting: @targeting).target_rows
  end
end
