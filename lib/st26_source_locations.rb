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
  Finding = Data.define(:submission, :accession, :entry_id, :entry_index, :source_index, :measured, :location, :expected, :reason) do
    # Whether `expected` is a value this task could write. Whether it *will* is
    # the Plan's: `:overrun` always, `:short` only where a person has said so
    # for that accession.
    def repairable? = %i[overrun short].include?(reason)
  end

  # What `fix` says when it will not rewrite something, per reason.
  REFUSALS = {
    unreadable:      ->(n) { "Refusing to rewrite #{n} #{'location'.pluralize(n)} bio-ruby cannot parse: whatever #{n == 1 ? 'it was' : 'they were'} trying to say would be destroyed." },
    short:           ->(n) { "Not lengthening #{n} #{'location'.pluralize(n)} that #{n == 1 ? 'stops' : 'stop'} short of the sequence. Read the sequence= column, decide per record, and name the ones you have confirmed in LENGTHEN — this cannot tell a boundary slip of two residues from a deliberate partial coverage of five hundred." },
    multiple_sources: ->(n) { "Not lengthening #{n} #{'location'.pluralize(n)} in #{'an entry'.pluralize(n)} carrying more than one source: widening one would swallow the next one's span. Fix #{n == 1 ? 'it' : 'them'} by hand." },
    ambiguous:       ->(n) { "Refusing to rewrite #{n} #{'location'.pluralize(n)} that #{n == 1 ? 'is' : 'are'} not a plain forward range from base 1: split, complemented, partial (<1..>N), fuzzy (1..(5.10)) and cross-referenced locations all say something that setting the full span would throw away. Fix #{n == 1 ? 'it' : 'them'} by hand." },
    missing:         ->(n) { "Refusing to fill in #{n} absent #{'location'.pluralize(n)}: a source feature with none at all is a different repair from this one. Fix #{n == 1 ? 'it' : 'them'} by hand." },
    no_sequence:     ->(n) { "Refusing to measure #{n} #{'entry'.pluralize(n)} with no sequence: there is no length for a location to agree with. Fix #{n == 1 ? 'it' : 'them'} by hand." },
    declared_length: ->(n) { "Refusing to touch #{n} #{'entry'.pluralize(n)} whose declared length disagrees with its sequence: which of the two was meant is not this task's to decide. Fix #{n == 1 ? 'it' : 'them'} by hand." }
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

  # The accession list as the audit will read it. Exposed so a caller that
  # demands a scope can refuse an empty one *before* the audit streams every
  # record in the archive out of object storage.
  def requested_from(accessions) = accessions.to_s.split(/[\s,]+/).reject(&:blank?).uniq

  # What a run will act on, shared by `report` and `fix` so the column that says
  # what will happen and the code that makes it happen cannot disagree.
  #
  # An overrun is repaired unconditionally: a location cannot name bases the
  # sequence does not have, whatever the amount, and setting the full span only
  # ever shrinks it.
  #
  # A shortfall is repaired only for an accession named in `LENGTHEN`. Per
  # accession and not per run, because the judgement is per record — a slip of
  # two residues and a deliberate coverage of five hundred look identical here,
  # and PATENT-386's answer came from a person looking at two specific entries.
  # A run-wide switch would carry that answer to every short row in the batch.
  Plan = Data.define(:lengthen) do
    def actionable?(finding)
      case finding.reason
      when :overrun then true
      when :short   then lengthen.include?(finding.accession)
      else               false
      end
    end
  end

  def plan_from(lengthen) = Plan.new(lengthen: requested_from(lengthen).to_set)

  def audit(accessions = nil)
    requested = requested_from(accessions)

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

      # Only when there is something to match against. Unscoped — the audit
      # task's normal use — this held every accession in the archive for the
      # length of the run to compute `[] - matched`.
      matched.concat accessions_by_entry.values if requested.any?

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

  def report(result, plan = plan_from(nil))
    # The last column is what will happen to this row, so it has to be read
    # against the run that is about to happen: `plan` is what tells a short row
    # authorised by LENGTHEN from one that is not, and a sibling from a target.
    # A footnote would not do — reading `-> 1..20` on a row that is going to be
    # left alone promises a rewrite that is not coming, and the inverse hides
    # one that is.
    siblings = result.siblings.to_set

    # The sequence length is on every row, refused ones included. It is the
    # number the decision turns on — whether a location falls short or runs
    # past, and by how much — and printing it only against rows that were going
    # to be rewritten anyway meant looking it up by hand for the ones that
    # actually needed a judgement.
    result.findings.each do |f|
      puts format(
        '%-12s submission #%-6d %-40s %-20s sequence=%-7d %s',
        f.accession || '(no accession)',
        f.submission.id,
        f.entry_id,
        f.location.presence || '(none)',
        f.measured,
        if siblings.include?(f)
          'NOT REWRITTEN (not named)'
        elsif plan.actionable?(f)
          "-> #{f.expected}"
        elsif f.reason == :short
          "-> #{f.expected} only if you name it in LENGTHEN"
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

  # Two passes. The first re-reads every named record and checks that what the
  # audit found is still there; only then is anything written. The check used to
  # fire mid-loop, so a batch whose third submission tripped it aborted with the
  # first two already rewritten — "nothing was written" was what the message
  # implied and not what had happened.
  #
  # The first pass streams and keeps nothing: an ST.26 submission can carry tens
  # of thousands of entries (see Submission#accession_summary), which is why
  # `scan` and the flatfile renderer stream rather than hold a document. Holding
  # a parsed copy of every submission in the batch, plus a serialised String of
  # each, would put the whole batch in memory at once. The rewrite still needs
  # one whole document, so memory is bounded by the largest single record.
  def correct!(findings)
    by_submission = findings.group_by(&:submission)

    by_submission.each { verify! it.first, it.last }

    # One transaction for the batch, so a failure part-way through does not
    # leave some records corrected and others not. The uploads themselves are
    # not transactional; a rollback leaves orphan blobs behind, which is the
    # same trade the rest of this system already makes.
    #
    # Printed after it commits, not inside: a rollback would otherwise have
    # already told the operator that records were rewritten.
    written = []

    Submission.transaction do
      by_submission.each do |submission, group|
        written << rewrite!(submission, group)
      end
    end

    written.each { puts it }
  end

  # That the audited disagreement is still in the record, in the same place and
  # with the same text. The old check only counted how many index pairs it hit,
  # so a record that had changed shape since the audit could be rewritten at
  # positions that now meant something else.
  def verify!(submission, group)
    # `expected` and `reason` are in the key as well as `location`. `expected`
    # carries the sequence length the audit measured, so a sequence that changed
    # since then cannot pass. `reason` carries everything else the
    # classification depends on: an entry that gained a second source feature
    # between audit and rewrite scores `:multiple_sources` where it scored
    # `:short`, with position, text and length all unchanged — so without it,
    # the very case the sources guard exists for would slip through.
    key     = ->(f) { [f.entry_index, f.source_index, f.location, f.expected, f.reason] }
    present = Array(scan(submission, {})).to_set(&key)
    wanted  = group.to_set(&key)
    missing = wanted - present

    return if missing.empty?

    raise "submission ##{submission.id}: #{missing.size} of #{group.size} audited #{'location'.pluralize(group.size)} " \
          'no longer look as they did — the record changed since the audit. Nothing has been written; run the audit again.'
  end

  # Rewrites the stored record in place. The raw JSON is mutated rather than
  # re-serialised from the parsed Data objects: the blob is the archived record,
  # and a round trip through the parser would rewrite fields this correction has
  # no business touching.
  #
  # `with_lock` because this is a read-modify-write of the blob and so is
  # RegenerateSubmissionFlatfilesJob — two of them interleaving would silently
  # drop one. Submission#append_update! takes the same lock for the same
  # reason. It does not serialise against a regenerate run, which takes no
  # lock; what it does do is stop two corrections from racing, and leave a
  # record of the intent where anybody adding a third writer will see it.
  #
  # `update!` and not `attach`: Attached::One#attach swallows a failed save and
  # returns nil, and Submission validates ddbj_record's content type on update —
  # so a submission whose stored blob carries a different one would have been
  # reported as rewritten while nothing was written.
  #
  # The bytes are uploaded through `create_and_upload!` before the attachment is
  # switched, rather than by handing an `io:` to the setter. The setter uploads
  # in an `after_commit`, and replacing the attachment purges the old blob — so
  # a storage failure at that point would leave the record pointing at a file
  # that was never written, with the only readable copy already gone. Uploading
  # first means such a failure raises while the old record is still attached.
  #
  # The old blob is still purged once the switch commits. What makes the
  # correction reversible is the report: it names every location's previous text
  # against its accession and entry, and the rewrite touches nothing else.
  def rewrite!(submission, group)
    submission.with_lock do
      wanted = group.to_h { [[it.entry_index, it.source_index], it] }
      json   = submission.ddbj_record.open { Oj.load(it.read, mode: :strict) }
      done   = 0

      Array(json.dig('sequences', 'entries')).each_with_index do |entry, i|
        Array(entry['source_features']).each_with_index do |sf, j|
          finding = wanted[[i, j]] or next

          raise "submission ##{submission.id}: #{finding.entry_id} source #{j} now reads #{sf['location'].inspect}, not #{finding.location.inspect}" unless sf['location'] == finding.location

          sf['location'] = finding.expected
          done          += 1
        end
      end

      raise "submission ##{submission.id}: expected to rewrite #{group.size} #{'location'.pluralize(group.size)}, found #{done}" unless done == group.size

      blob = ActiveStorage::Blob.create_and_upload!(
        io:           StringIO.new(Oj.dump(json, mode: :strict)),
        filename:     submission.ddbj_record.filename.to_s,
        content_type: submission.ddbj_record.content_type
      )

      submission.update! ddbj_record: blob

      "submission ##{submission.id}: rewrote #{done} #{'location'.pluralize(done)}"
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

        add = ->(source_index, location, reason) {
          findings << Finding.new(
            submission:,
            accession:   accessions_by_entry[entry.id],
            entry_id:    entry.id,
            entry_index: i,
            source_index:,
            measured:,
            location:,
            expected:    "1..#{measured}",
            reason:
          )
        }

        # An entry with no sequence has no length to measure a location
        # against. Reported rather than passed over: this used to be a bare
        # `next`, so the audit could call the archive clean over an entry it had
        # not examined.
        if measured.zero?
          add.call nil, '(no sequence)', :no_sequence

          next
        end

        # Reported against the entry rather than a single source feature, and
        # never rewritten: correcting the locations to match a wrong length
        # would leave the record still wrong while this task's own re-audit
        # called it clean.
        if declared && declared != measured
          add.call nil, "declared length #{declared}", :declared_length

          next
        end

        sources = Array(entry.source_features)

        sources.each_with_index do |sf, j|
          reason = disagreement(sf.location, measured, sources: sources.size) or next

          add.call j, sf.location, reason
        end
      end

      findings
    end
  end

  # nil when the location is fine, otherwise why it is not. Two of the reasons
  # carry a value this task knows how to write (`:overrun`, `:short`); see Plan
  # for which of those a given run will act on.
  #
  # PATENT-386's five records disagree in both directions: three run one base
  # past the end (`1..449` over 448) and two stop short (`1..315` over 316). An
  # ST.26 patent source covers the whole sequence — the premise the ticket's own
  # FF spec is built on, and submission-bulk-st26 pins the location to
  # `1..<length>` either way — so that is what such a range meant.
  #
  # Everything else keeps its shape. A split, complemented, partial (`<1..>21`),
  # fuzzy (`1..(5.10)`) or cross-referenced location, or one that does not start
  # at base 1, says something that setting the full span would throw away, and
  # no premise about patent sources tells us which part of it was the mistake.
  def disagreement(location, length, sources: 1)
    return :missing if location.blank?

    span = Bio::Locations.new(location.to_s).span

    return nil if span == [1, length]

    # Matched against the text, not against bio-ruby's numbers. It flattens a
    # fuzzy bound — `1..(5.10)` comes back as from=1/to=10 and `1.5` as 1..1,
    # both with every marker nil — so a check reading `from` and `to` takes
    # those for plain ranges and would rewrite the notation away. One regexp
    # also excludes `<1..>21`, `J00194.1:1..21`, `complement(…)`, `join(…)` and
    # a bare `1`, each of which says something the full span does not.
    #
    # Whitespace is tolerated because these strings are lifted verbatim out of
    # XML, which is where a stray space comes from; `expected` is the normalised
    # `1..<length>` either way. Refusing them would blame the notation for a
    # defect that is plainly the numbers.
    m = /\A\s*(\d+)\s*\.\.\s*(\d+)\s*\z/.match(location.to_s)

    return :ambiguous unless m && m[1] == '1'

    return :overrun if m[2].to_i > length

    # Only the widening direction is affected: the premise that a patent source
    # covers the whole sequence is a statement about an entry with one source,
    # and where several divide an entry — which the v2 schema provides for —
    # lengthening the first would swallow the next one's span. Shrinking an
    # overrun above cannot do that, so it is not gated here.
    sources == 1 ? :short : :multiple_sources
  rescue StandardError
    :unreadable
  end
end
