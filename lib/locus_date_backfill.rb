# Puts `entries.locus_date` back to the date the publication operator chose.
#
# Until 2026-08 the apply job wrote the apply date into the column while the
# flatfile printed the date carried in the record, so the two disagree on every
# submission applied before that — and regeneration renders from the column, so
# regenerating one of them moves its published LOCUS date. See CLAUDE.md, "The
# LOCUS date".
#
# The original is read from the **request's** record, the file as the operator
# uploaded it. The submission's own record is rewritten by every regeneration,
# so for a submission that has been regenerated it already holds the apply date
# and cannot say what was meant; the request's copy is never rewritten.
#
# A one-off, like the PATENT-386 repair before it: delete it once the archive has
# been walked. Unlike that one it commits per submission rather than in a single
# transaction — 18,000 submissions cannot be one — so it is written to be
# re-runnable and to report exactly what it changed.
module LocusDateBackfill
  Change = Data.define(:entry, :from, :to)

  Unexamined = Data.define(:submission, :why)

  Result = Data.define(:changes, :unexamined, :scanned) do
    def submissions = changes.map { it.entry.submission_id }.uniq
  end

  module_function

  # `except` names entries to leave alone: an entry whose date was deliberately
  # set to something other than the operator's original — PATENT-386's five —
  # would otherwise be pulled back to what the request said.
  def audit(limit: nil, after: nil, accessions: nil, except: nil)
    keep    = split(except).to_set
    named   = split(accessions)
    changes = []
    unex    = []
    scanned = 0

    scope = Submission.st26_db.order(:id)
    scope = scope.where(id: Entry.where(accession: named).select(:submission_id)) if named.any?
    scope = scope.where(id: after.to_i..)                                        if after.present?
    scope = scope.limit(limit.to_i)                                              if limit.present?

    scope.each do |submission|
      scanned += 1

      wanted = original_dates(submission)

      next unex << Unexamined.new(submission:, why: wanted) if wanted.is_a?(String)

      submission.entries.order(:accession).each do |entry|
        next if keep.include?(entry.accession)

        was = wanted[entry.entry_id]

        next if was.blank? || was == entry.locus_date

        changes << Change.new(entry:, from: entry.locus_date, to: was)
      end
    end

    Result.new(changes:, unexamined: unex, scanned:)
  end

  def report(result)
    result.changes.each do |c|
      puts format('%-12s submission #%-6d LOCUS date %s -> %s', c.entry.accession, c.entry.submission_id, c.from, c.to)
    end

    result.unexamined.each do |u|
      puts format('%-12s submission #%-6d not examined: %s', '(skipped)', u.submission.id, u.why)
    end
  end

  # Per submission, so a long run can be stopped and resumed. Each entry is
  # written by id with its expected current value in the WHERE clause: the audit
  # and the write are separate reads, and a date that moved in between is one
  # this run no longer knows the truth about.
  def apply!(changes)
    changes.group_by { it.entry.submission_id }.map do |submission_id, group|
      written = 0

      Entry.transaction do
        group.each do |c|
          written += Entry.where(id: c.entry.id, locus_date: c.from).update_all(locus_date: c.to, updated_at: Time.current)
        end

        raise "submission ##{submission_id}: expected to redate #{group.size} #{'entry'.pluralize(group.size)}, redated #{written} — the dates moved since the audit" unless written == group.size
      end

      "submission ##{submission_id}: redated #{written} #{'entry'.pluralize(written)}"
    end
  end

  # entry_id => Date from the request's record, or a string saying why not.
  def original_dates(submission)
    request = SubmissionRequest.find_by(submission_id: submission.id)

    return 'no submission request' unless request
    return 'request has no record' unless request.ddbj_record.attached?

    request.ddbj_record.open do |file|
      major, = DDBJRecord::SchemaVersionDetector.detect(file)
      file.rewind

      next 'v3 record' if major == '3'

      DDBJRecord::StreamingParser.new(file.path).each_entry.to_h { [it.id, parse(it.locus_date)] }
    end
  rescue StandardError => e
    "#{e.class}: #{e.message}"
  end

  # Only `YYYY-MM-DD`, for the reason ApplySubmissionRequestJob refuses anything
  # else: `Date.parse` would guess, and the guess lands on a published flatfile.
  # A date this cannot read leaves the entry alone rather than moving it
  # somewhere invented.
  def parse(value)
    return nil unless value.to_s.match?(ApplySubmissionRequestJob::LOCUS_DATE_FORMAT)

    Date.iso8601(value)
  rescue Date::Error
    nil
  end

  def split(value) = value.to_s.split(/[\s,]+/).reject(&:blank?).uniq
end
