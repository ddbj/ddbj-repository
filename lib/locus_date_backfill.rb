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
# uploaded it. The submission's own record is rewritten by every regeneration, so
# for a submission that has already been regenerated it holds the apply date and
# cannot say what was meant; the request's copy is never rewritten.
#
# Three things are deliberately left alone, each reported rather than passed over
# in silence:
#
# - An entry whose `locus_date` is no longer the date its row was created. It no
#   longer carries the apply stamp, so somebody set it on purpose — PATENT-386's
#   five, redated to 2026-08-13, are why this matters — and restoring "what the
#   request asked for" over that would undo their work. No list of exceptions to
#   remember. (Reported only when it also differs from the request's date: after
#   the apply job started reading the record, a correctly dated new submission
#   has a column that differs from its `created_at` too.)
# - A submission that has already been regenerated. Its record was rewritten with
#   the column's apply date, so the two agree today, and moving only the column
#   would put them into the disagreement the guard refuses — leaving the
#   submission unregeneratable, with a second pass unable to help because the
#   stamp is gone. Those are also the submissions whose *published* flatfile
#   prints the apply date, so the column is not the thing to fix: they need a
#   regeneration that names the date, which writes the column, the record and the
#   file together.
# - An entry whose original date cannot be read (`2026-8-13`). Guessing at a date
#   is what put a wrong one on a flatfile to begin with.
#
# No EntryHistory row: this changes what the column says, not what the record or
# the published flatfile says. The date is not moving — it is being recorded where
# it was already meant to be.
#
# A one-off. Delete it once the archive has been walked.
module LocusDateBackfill
  ALREADY_REGENERATED = 'already regenerated: its record and its published flatfile carry the apply date, so redate it ' \
                        'with `Regenerate flatfiles` naming the date — this cannot fix it'.freeze

  Change = Data.define(:entry, :from, :to)

  # One submission's worth of work, and everything about it a person has to see.
  # `unexamined` is a reason the submission was not looked at; `unreadable` names
  # entries whose original date could not be read; `deliberate` names entries
  # somebody had already dated.
  Outcome = Data.define(:submission, :changes, :unexamined, :unreadable, :deliberate) do
    def examined? = unexamined.nil?

    def needs_attention? = !examined? || unreadable.any?
  end

  module_function

  # Yields an Outcome per submission and holds nothing: the archive is ~18,000
  # submissions and every one of them means a blob read, so a pass that collected
  # first and acted later would carry the whole thing in memory.
  def each_submission(limit: nil, after: nil, accessions: nil)
    return enum_for(:each_submission, limit:, after:, accessions:) unless block_given?

    named = split(accessions).to_set

    # No `order`: `find_each` batches by id and discards any order of its own.
    # `AFTER` is exclusive, or resuming would re-read the blob of the submission
    # the previous run stopped on.
    scope = Submission.st26_db
    scope = scope.where(id: Entry.where(accession: named.to_a).select(:submission_id)) if named.any?
    scope = scope.where(id: (integer!(after, 'AFTER') + 1)..)                          if after.present?
    scope = scope.limit(integer!(limit, 'LIMIT'))                                      if limit.present?

    scope.find_each { yield examine(it, named) }
  end

  def examine(submission, named)
    return unexamined(submission, ALREADY_REGENERATED) if regenerated?(submission)

    wanted = original_dates(submission)

    return unexamined(submission, wanted) if wanted.is_a?(String)

    changes    = []
    unreadable = []
    deliberate = []

    submission.entries.order(:accession).each do |entry|
      # Named entries only, when any were named. `ACCESSIONS` reaches whole
      # submissions to find the records, and a submission can hold sixty
      # entries — restoring the other fifty-nine was not what was asked for.
      next if named.any? && !named.include?(entry.accession)

      was = wanted[entry.entry_id]

      unless entry.locus_date == entry.created_at.to_date
        # Named only when it is also not the date the request asked for. After
        # this deploy every correctly dated new submission has a column that
        # differs from its `created_at` — the operator dates a batch days ahead —
        # so naming all of those would bury the ones somebody really did redate
        # (PATENT-386's five) in routine data.
        next deliberate << entry.accession if was.is_a?(Date) && was != entry.locus_date

        next
      end

      next unreadable << entry.accession if was == :unreadable
      next if was.nil? || was == entry.locus_date

      changes << Change.new(entry:, from: entry.locus_date, to: was)
    end

    Outcome.new(submission:, changes:, unexamined: nil, unreadable:, deliberate:)
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
    id = outcome.submission.id

    return [format('(skipped)    submission #%-6d %s', id, outcome.unexamined)] unless outcome.examined?

    outcome.changes.map { format('%-12s submission #%-6d LOCUS date %s -> %s', it.entry.accession, id, it.from, it.to) } +
      outcome.unreadable.map { format('%-12s submission #%-6d its request spells the date in a way this will not guess at', it, id) } +
      outcome.deliberate.map { format('%-12s submission #%-6d left alone: its date was set after it was applied, and is not the one its request asked for', it, id) }
  end

  # Which of the named accessions the run never saw. A typo, the wrong case, or a
  # number outside the archive would otherwise read as "nothing to do here".
  def unmatched(accessions, seen) = split(accessions).to_set - seen

  # Whether this submission's record has already been rewritten by a
  # regeneration. Read from the history rather than by comparing the two records,
  # which would double the blob reads of an archive-wide pass.
  def regenerated?(submission)
    EntryHistory.where(action: 'regenerate', entry_id: submission.entries.select(:id)).exists?
  end

  # entry_id => Date, `:unreadable`, or nil when the request named no date. A
  # String in place of the Hash is the reason the submission could not be read.
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

  # nil when the record names no date, `:unreadable` when it names one this will
  # not guess at, otherwise the date.
  def parse(value)
    return nil if value.blank?
    return :unreadable unless value.to_s.match?(DDBJRecord::LOCUS_DATE_FORMAT)

    Date.iso8601(value)
  rescue Date::Error
    :unreadable
  end

  def unexamined(submission, why) = Outcome.new(submission:, changes: [], unexamined: why, unreadable: [], deliberate: [])

  def split(value) = value.to_s.split(/[\s,]+/).reject(&:blank?).uniq

  # `AFTER=LC000123` would otherwise be 0 and silently restart a resumed run;
  # `LIMIT=all` would be `limit(0)`, which scans nothing and reads as clean.
  def integer!(value, name)
    Integer(value.to_s, 10)
  rescue ArgumentError
    raise ArgumentError, "#{name}=#{value} is not a number."
  end
end
