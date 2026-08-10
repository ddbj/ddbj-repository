# The audit and correction behind `rake st26:source_locations:*`. A one-off for
# INSDC-3468 / PATENT-386 rather than a feature, so it lives in lib/ next to
# the tasks that call it and goes away with them — but in a file of its own,
# because it is the only code in that change that rewrites an archived record
# and it needs tests.
module St26SourceLocations
  # `entry_index` / `source_index` and not the ids: `source_features[].id` is
  # optional in the record (Builders#build_source_feature), so two sources in
  # one entry can share a nil id. Keying the rewrite on that would rewrite both
  # and then trip the count guard — after earlier submissions in the batch had
  # already been written.
  Finding = Data.define(:submission, :accession, :entry_id, :entry_index, :source_index, :location, :expected, :reason) do
    # Only an overrun is: see St26SourceLocations.disagreement. Everything
    # else is a question about what was meant, and this task does not get to
    # answer those — it would be inventing coverage, or discarding what a
    # location was trying to say.
    def correctable? = reason == :overrun
  end

  # What `fix` says when it will not rewrite something, per reason.
  REFUSALS = {
    unreadable:      ->(n) { "Refusing to rewrite #{n} #{'location'.pluralize(n)} bio-ruby cannot parse: whatever #{n == 1 ? 'it was' : 'they were'} trying to say would be destroyed." },
    ambiguous:       ->(n) { "Refusing to widen #{n} #{'location'.pluralize(n)} covering less than the whole sequence, or covering it in several pieces: rewriting to the full span would invent coverage nobody declared." },
    missing:         ->(n) { "Refusing to fill in #{n} absent #{'location'.pluralize(n)}: a source feature with none at all is a different repair from this one." },
    declared_length: ->(n) { "Refusing to touch #{n} #{'entry'.pluralize(n)} whose declared length disagrees with its sequence: which of the two was meant is not this task's to decide." }
  }.freeze

  Unreadable = Data.define(:submission, :error)

  # Why a submission was not examined, in words the report can print.
  Skipped = Data.define(:submission, :why)

  Result = Data.define(:findings, :unreadable, :skipped, :unmatched, :requested) do
    # Split so `fix` can act on what was asked for while the operator still
    # sees the rest: a sibling entry in the same submission is worth knowing
    # about, but rewriting it was not what anybody asked for.
    def named = requested.empty? ? findings : findings.select { requested.include?(it.accession) }

    def siblings = named == findings ? [] : findings - named
  end

  module_function

  def audit(accessions = nil)
    requested = accessions.to_s.split(/[\s,]+/).reject(&:blank?).uniq

    # Not `where.associated(:ddbj_record_attachment)`: a submission with no
    # record at all was then invisible, so an unscoped audit pronounced the
    # archive clean over it and a scoped one reported its accession as matching
    # nothing — sending the operator after a typo that was not there. They
    # exist: ApplySubmissionRequestJob commits `create_submission!` before the
    # record is attached, so any failure in between leaves one behind.
    scope = Submission.st26_db
    scope = scope.where(id: Entry.where(accession: requested).select(:submission_id)) if requested.any?

    findings   = []
    unreadable = []
    skipped    = []
    matched    = []

    scope.find_each do |submission|
      accessions_by_entry = submission.entries.pluck(:entry_id, :accession).to_h
      matched.concat accessions_by_entry.values

      unless submission.ddbj_record.attached?
        skipped << Skipped.new(submission:, why: 'no record attached')

        next
      end

      begin
        found = scan(submission, accessions_by_entry)

        # `scan` returns nil for a record it declined to read rather than an
        # empty list, so that "nothing wrong here" and "not looked at" cannot
        # be confused downstream.
        found ? findings.concat(found) : skipped << Skipped.new(submission:, why: 'v3 record')
      rescue StandardError => e
        # One missing blob used to abort the whole scan and print nothing, so
        # every finding gathered before it was lost. Reported as its own line
        # instead — an unreadable record is a finding too.
        unreadable << Unreadable.new(submission:, error: e)
      end
    end

    Result.new(findings:, unreadable:, skipped:, unmatched: requested - matched, requested: requested.to_set)
  end

  def report(result)
    # The last column is what will happen to this row, so a sibling has to say
    # so there rather than in a footnote: it is a disagreement that will be
    # left alone, and reading `-> 1..20` against it promises a rewrite that is
    # not coming.
    siblings = result.siblings.to_set

    result.findings.each do |f|
      puts format(
        '%-12s submission #%-6d %-40s %-20s -> %s',
        f.accession || '(no accession)',
        f.submission.id,
        f.entry_id,
        f.location.presence || '(none)',
        if siblings.include?(f)
          'NOT REWRITTEN (not named)'
        elsif f.correctable?
          f.expected
        else
          "NOT REWRITTEN (#{f.reason})"
        end
      )
    end

    result.unreadable.each do |u|
      puts format('%-12s submission #%-6d could not be read: %s', '(unreadable)', u.submission.id, u.error.message)
    end

    result.skipped.each do |s|
      puts format('%-12s submission #%-6d not examined: %s', '(skipped)', s.submission.id, s.why)
    end

    return if result.unmatched.empty?

    # An accession that matches nothing is far more likely to be a typo than a
    # record that is fine, and "OK" is the wrong thing to tell somebody who
    # mistyped one of five numbers.
    puts "\n#{result.unmatched.size} #{'accession'.pluralize(result.unmatched.size)} matched no ST.26 entry: #{result.unmatched.join(', ')}"
  end

  # Rewrites the stored record in place. The raw JSON is mutated rather than
  # re-serialised from the parsed Data objects: the blob is the archived
  # record, and a round trip through the parser would rewrite fields this
  # correction has no business touching.
  # Every record is read and checked before any of them is written. The count
  # guard used to fire mid-loop, so a batch whose third submission tripped it
  # aborted with the first two already rewritten — "nothing was written" was
  # what the message implied and not what had happened.
  def correct!(findings)
    prepared = findings.group_by(&:submission).map {|submission, group|
      wanted = group.to_h { [[it.entry_index, it.source_index], it.expected] }

      json      = submission.ddbj_record.open { Oj.load(it.read, mode: :strict) }
      rewritten = 0

      Array(json.dig('sequences', 'entries')).each_with_index do |entry, i|
        Array(entry['source_features']).each_with_index do |sf, j|
          expected = wanted[[i, j]] or next

          sf['location'] = expected
          rewritten     += 1
        end
      end

      raise "submission ##{submission.id}: expected to rewrite #{group.size} #{'location'.pluralize(group.size)}, found #{rewritten} — nothing has been written" unless rewritten == group.size

      [submission, json, rewritten]
    }

    # `update!` and not `attach`: Attached::One#attach swallows a failed save
    # and returns nil, and Submission validates ddbj_record's content type on
    # update — so a submission whose stored blob carries a different one would
    # have been reported as rewritten while nothing was written.
    #
    # One transaction for the batch, so a failure part-way through does not
    # leave some records corrected and others not. The uploads themselves are
    # not transactional; a rollback leaves orphan blobs behind, which is the
    # same trade the rest of this system already makes.
    Submission.transaction do
      prepared.each do |submission, json, rewritten|
        submission.update!(
          ddbj_record: {
            io:           StringIO.new(Oj.dump(json, mode: :strict)),
            filename:     submission.ddbj_record.filename.to_s,
            content_type: submission.ddbj_record.content_type
          }
        )

        puts "submission ##{submission.id}: rewrote #{rewritten} #{'location'.pluralize(rewritten)}"
      end
    end
  end

  # Reads the record the way the flatfile renderer does — through the parser,
  # not the raw JSON — so a finding here is a finding the renderer would act
  # on. Streams, because an unscoped audit covers every ST.26 submission.
  def scan(submission, accessions_by_entry)
    submission.ddbj_record.open do |file|
      major, = DDBJRecord::SchemaVersionDetector.detect(file)
      file.rewind

      # v3 entries carry no `length`, and no v3 record reaches the flatfile
      # renderer yet. nil rather than an empty list, so the caller can tell
      # "not examined" from "nothing wrong here" — this used to warn to stderr
      # while the summary went on to call the archive clean.
      next nil if major == '3'

      findings = []

      DDBJRecord::StreamingParser.new(file.path).each_entry.with_index do |entry, i|
        # Measured from the sequence, not from the declared `length`. The v2
        # schema has no length field at all (it is a server extension this
        # system adds), so measuring by it skipped every record that lacks one,
        # and where the length was the wrong half of the disagreement it
        # pronounced the entry clean.
        measured = entry.sequence.to_s.size
        declared = entry.length&.to_i

        next unless measured.positive?

        add = ->(source_index, location, reason) {
          findings << Finding.new(
            submission:,
            accession:   accessions_by_entry[entry.id],
            entry_id:    entry.id,
            entry_index: i,
            source_index:,
            location:,
            expected:    "1..#{measured}",
            reason:
          )
        }

        # Reported against the entry rather than a single source feature, and
        # never rewritten: correcting the locations to match a wrong length
        # would leave the record still wrong while this task's own re-audit
        # called it clean.
        if declared && declared != measured
          add.call nil, "declared length #{declared}", :declared_length

          next
        end

        Array(entry.source_features).each_with_index do |sf, j|
          reason = disagreement(sf.location, measured) or next

          add.call j, sf.location, reason
        end
      end

      findings
    end
  end

  # nil when the location is fine, otherwise why it is not — and only one of
  # those reasons is something this task will rewrite.
  #
  # `:overrun` is the JPO defect and nothing else: one plain forward range that
  # starts at 1 and runs past the end, where `1..<length>` is what was plainly
  # meant. Every other disagreement would have coverage invented for it — a
  # location covering 1..500 of 1000 bases, or `join(1..4,6..9)` with its gap
  # at 5, does not become correct by being widened to the whole sequence, it
  # becomes a different claim.
  def disagreement(location, length)
    return :missing if location.blank?

    locations = Bio::Locations.new(location.to_s)
    span      = locations.span

    return nil if span == [1, length]

    only = locations.locations.size == 1 ? locations.locations.first : nil

    # Plain means plain: `<1..>21` carries 5'/3' partiality and
    # `J00194.1:1..21` points into another accession, and both of those would
    # be thrown away by rewriting the string to `1..<length>`. bio-ruby keeps
    # them as `lt` / `gt` / `xref_id` / `carat` beside the numbers, so a check
    # that reads only `from` and `to` cannot see them.
    plain = only &&
            only.strand == 1 &&
            [only.lt, only.gt, only.xref_id, only.carat].all?(&:nil?) &&
            only.from == 1 &&
            only.to.to_i > length

    plain ? :overrun : :ambiguous
  rescue StandardError
    :unreadable
  end
end
