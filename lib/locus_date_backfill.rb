# Puts `entries.locus_date` back to the date the publication operator chose.
#
# Until 2026-08 the apply job wrote the apply date into the column while the
# flatfile printed the date carried in the record, so the two disagree on every
# submission applied before that. Regeneration renders from the column, so
# RegenerateSubmissionFlatfilesJob now refuses a submission whose column and
# record disagree — which is what makes this a prerequisite rather than a
# tidy-up. See CLAUDE.md, "The LOCUS date".
#
# The original is read from the **request's** record, the file as the operator
# uploaded it. The submission's own record is rewritten by every regeneration,
# so for a submission that has already been regenerated it holds the apply date
# and cannot say what was meant; the request's copy is never rewritten.
#
# An entry is left alone unless it still carries the apply stamp — that is,
# unless `locus_date` is the date the row was created. Anything else was set by
# somebody on purpose (PATENT-386's five, redated to 2026-08-13, are the reason
# this matters), and restoring "the date the request asked for" over a
# deliberate one would undo their work. No list of exceptions to remember.
#
# No EntryHistory row: this changes what the column says, not what the record or
# the published flatfile says. The date is not moving — it is being recorded
# where it was already meant to be.
#
# A one-off. Delete it once the archive has been walked.
module LocusDateBackfill
  Change = Data.define(:entry, :from, :to)

  # One submission's worth of work, or the reason there is none.
  Outcome = Data.define(:submission, :changes, :unexamined) do
    def examined? = unexamined.nil?
  end

  module_function

  # Yields an Outcome per submission and holds nothing: the archive is ~18,000
  # submissions and every one of them means a blob read, so a pass that
  # collected first and acted later would carry the whole thing in memory.
  def each_submission(limit: nil, after: nil, accessions: nil)
    return enum_for(:each_submission, limit:, after:, accessions:) unless block_given?

    named = split(accessions).to_set
    scope = Submission.st26_db.order(:id)
    scope = scope.where(id: Entry.where(accession: named.to_a).select(:submission_id)) if named.any?
    scope = scope.where(id: integer!(after, 'AFTER')..)                                if after.present?
    scope = scope.limit(integer!(limit, 'LIMIT'))                                      if limit.present?

    scope.find_each { yield examine(it, named) }
  end

  def examine(submission, named)
    wanted = original_dates(submission)

    return Outcome.new(submission:, changes: [], unexamined: wanted) if wanted.is_a?(String)

    changes = submission.entries.order(:accession).filter_map {|entry|
      # Named entries only, when any were named. `ACCESSIONS` reaches whole
      # submissions to find the records, and a submission can hold sixty
      # entries — restoring the other fifty-nine was not what was asked for.
      next if named.any? && !named.include?(entry.accession)

      # Still bearing the apply stamp, or somebody set it deliberately.
      next unless entry.locus_date == entry.created_at.to_date

      was = wanted[entry.entry_id]

      next if was.blank? || was == entry.locus_date

      Change.new(entry:, from: entry.locus_date, to: was)
    }

    Outcome.new(submission:, changes:, unexamined: nil)
  end

  # Per submission, so a long run can be stopped and resumed, and each entry is
  # written with its expected current value in the WHERE clause: the read and the
  # write are separate, and a date that moved in between is one this no longer
  # knows the truth about.
  def apply!(changes)
    written = 0

    Entry.transaction do
      changes.each do |c|
        written += Entry.where(id: c.entry.id, locus_date: c.from).update_all(locus_date: c.to, updated_at: Time.current)
      end

      raise "submission ##{changes.first.entry.submission_id}: expected to redate #{changes.size} #{'entry'.pluralize(changes.size)}, redated #{written} — the dates moved since they were read" unless written == changes.size
    end

    written
  end

  def describe(outcome)
    return ["#{label(outcome.submission)} not examined: #{outcome.unexamined}"] unless outcome.examined?

    outcome.changes.map do |c|
      format('%-12s submission #%-6d LOCUS date %s -> %s', c.entry.accession, c.entry.submission_id, c.from, c.to)
    end
  end

  # Which of the named accessions the run never saw. A typo, the wrong case, or
  # a number outside the archive would otherwise read as "nothing to do here".
  def unmatched(accessions, seen)
    split(accessions).to_set - seen
  end

  # entry_id => Date from the request's record, or a string saying why not.
  def original_dates(submission)
    request = submission.request

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

  def label(submission) = format('(skipped)    submission #%-6d', submission.id)

  def split(value) = value.to_s.split(/[\s,]+/).reject(&:blank?).uniq

  # `AFTER=LC000123` would otherwise be 0 and silently restart a resumed run;
  # `LIMIT=all` would be `limit(0)`, which scans nothing and reads as clean.
  def integer!(value, name)
    Integer(value.to_s, 10)
  rescue ArgumentError
    raise ArgumentError, "#{name}=#{value} is not a number."
  end
end
