namespace :st26 do
  namespace :source_locations do
    # INSDC-3468 / PATENT-386. JPO ST.26 files carried source feature locations
    # taken verbatim from the XML, which overran the sequence (1..21 over 20
    # bases). The flatfile prints LOCUS from the length and both the source
    # location and the REFERENCE span from the location, so those records ship
    # claiming two different lengths.
    #
    # submission-bulk-st26 now pins the location to 1..<length> as it builds the
    # record (PAT_R0024), and TRD_R0013 refuses a mismatch at validation, so
    # this is only for the records that landed before either existed.

    desc 'Report ST.26 entries whose source location disagrees with the sequence length (ACCESSIONS= to scope)'
    task audit: :environment do
      result = ST26SourceLocations.audit(ENV['ACCESSIONS'])

      ST26SourceLocations.report result

      puts result.findings.empty? ? 'OK: every source location spans its sequence.' : "#{result.findings.size} disagreeing #{'location'.pluralize(result.findings.size)}."
    end

    desc 'Rewrite disagreeing source locations to 1..<length> (ACCESSIONS= required, APPLY=1 to write)'
    task fix: :environment do
      accessions = ENV['ACCESSIONS'].to_s

      # A blanket rewrite is refused. The correction is only ever right for
      # records already known to be wrong, and the audit is how they become
      # known — a bare `rake st26:source_locations:fix` would otherwise rewrite
      # the archive on the strength of a typo.
      abort 'ACCESSIONS is required: name the accessions to correct, comma or space separated.' if accessions.blank?

      result = ST26SourceLocations.audit(accessions)

      ST26SourceLocations.report result

      # Only what was named. Resolving accessions reaches whole submissions —
      # a JPO request can carry sixty entries — so without this, naming one
      # accession would rewrite every disagreeing sibling alongside it.
      correctable, rest = result.named.partition(&:correctable?)

      if rest.any?
        puts "\nRefusing to rewrite #{rest.size} unreadable #{'location'.pluralize(rest.size)} — a location bio-ruby cannot parse carries information this task would destroy. Fix those by hand."
      end

      abort "#{result.unmatched.size} #{'accession'.pluralize(result.unmatched.size)} matched no ST.26 entry — nothing was written." if result.unmatched.any?

      if correctable.empty?
        puts 'Nothing to correct.'
        next
      end

      unless ENV['APPLY'] == '1'
        puts "\nDry run. Re-run with APPLY=1 to rewrite #{correctable.size} #{'location'.pluralize(correctable.size)}."
        next
      end

      ST26SourceLocations.correct! correctable

      remaining = ST26SourceLocations.audit(accessions)

      if remaining.named.none?(&:correctable?)
        puts "\nCorrected. Every named source location now spans its sequence."
        puts 'The flatfiles still hold the old spans — regenerate them from Admin → Regenerate flatfiles for these accessions.'
      else
        ST26SourceLocations.report remaining
        abort 'Locations still disagree after the rewrite.'
      end
    end
  end
end

# Rake tasks are not a place to keep logic, but this is a one-off correction
# rather than a feature: putting it in app/ would leave a class behind that
# nothing calls once the five records are fixed. It lives here so it can be
# deleted with the tasks that use it.
module ST26SourceLocations
  # `entry_index` / `source_index` and not the ids: `source_features[].id` is
  # optional in the record (Builders#build_source_feature), so two sources in
  # one entry can share a nil id. Keying the rewrite on that would rewrite both
  # and then trip the count guard — after earlier submissions in the batch had
  # already been written.
  Finding = Data.define(:submission, :accession, :entry_id, :entry_index, :source_index, :location, :expected, :reason) do
    # An unreadable location has no `1..length` to be rewritten *to* without
    # discarding whatever it was trying to say.
    def correctable? = reason == :mismatch
  end

  Unreadable = Data.define(:submission, :error)

  Result = Data.define(:findings, :unreadable, :unmatched, :requested) do
    # Split so `fix` can act on what was asked for while the operator still
    # sees the rest: a sibling entry in the same submission is worth knowing
    # about, but rewriting it was not what anybody asked for.
    def named = requested.empty? ? findings : findings.select { requested.include?(it.accession) }

    def siblings = named == findings ? [] : findings - named
  end

  module_function

  def audit(accessions = nil, &progress)
    requested = accessions.to_s.split(/[\s,]+/).reject(&:blank?).uniq
    scope     = Submission.st26_db.where.associated(:ddbj_record_attachment)
    scope     = scope.where(id: Entry.where(accession: requested).select(:submission_id)) if requested.any?

    findings   = []
    unreadable = []
    matched    = []

    scope.find_each do |submission|
      progress&.call submission

      accessions_by_entry = submission.entries.pluck(:entry_id, :accession).to_h
      matched.concat accessions_by_entry.values

      begin
        findings.concat scan(submission, accessions_by_entry)
      rescue StandardError => e
        # One missing blob used to abort the whole scan and print nothing, so
        # every finding gathered before it was lost. Reported as its own line
        # instead — an unreadable record is a finding too.
        unreadable << Unreadable.new(submission:, error: e)
      end
    end

    Result.new(findings:, unreadable:, unmatched: requested - matched, requested: requested.to_set)
  end

  def report(result)
    result.findings.each do |f|
      puts format(
        '%-12s submission #%-6d %-40s %-16s -> %s',
        f.accession || '(no accession)',
        f.submission.id,
        f.entry_id,
        f.location.presence || '(none)',
        f.correctable? ? f.expected : "UNREADABLE (#{f.reason})"
      )
    end

    result.unreadable.each do |u|
      puts format('%-12s submission #%-6d could not be read: %s', '(unreadable)', u.submission.id, u.error.message)
    end

    if (siblings = result.siblings).any?
      named = siblings.map(&:accession).uniq

      puts "\nAlso disagreeing in the same submissions, not named and so not corrected: #{named.take(5).join(', ')}#{'…' if named.size > 5}"
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
  def correct!(findings)
    findings.group_by(&:submission).each do |submission, group|
      wanted = group.to_h { [[it.entry_index, it.source_index], it.expected] }

      json = submission.ddbj_record.open { Oj.load(it.read, mode: :strict) }

      rewritten = 0

      Array(json.dig('sequences', 'entries')).each_with_index do |entry, i|
        Array(entry['source_features']).each_with_index do |sf, j|
          expected = wanted[[i, j]] or next

          sf['location'] = expected
          rewritten     += 1
        end
      end

      raise "submission ##{submission.id}: expected to rewrite #{group.size} #{'location'.pluralize(group.size)}, rewrote #{rewritten}" unless rewritten == group.size

      submission.ddbj_record.attach(
        io:           StringIO.new(Oj.dump(json, mode: :strict)),
        filename:     submission.ddbj_record.filename.to_s,
        content_type: submission.ddbj_record.content_type
      )

      puts "submission ##{submission.id}: rewrote #{rewritten} #{'location'.pluralize(rewritten)}"
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
      # renderer yet. Named rather than skipped silently.
      if major == '3'
        warn "submission ##{submission.id}: skipped, v3 record"
        next []
      end

      findings = []

      DDBJRecord::StreamingParser.new(file.path).each_entry.with_index do |entry, i|
        length = entry.length.to_i

        next unless length.positive?

        Array(entry.source_features).each_with_index do |sf, j|
          reason = disagreement(sf.location, length) or next

          findings << Finding.new(
            submission:,
            accession:    accessions_by_entry[entry.id],
            entry_id:     entry.id,
            entry_index:  i,
            source_index: j,
            location:     sf.location,
            expected:     "1..#{length}",
            reason:
          )
        end
      end

      findings
    end
  end

  # nil when the location is fine. Distinguishes the two failures because they
  # get different treatment: a numeric mismatch can be rewritten to the full
  # span, an unparseable location cannot.
  def disagreement(location, length)
    span = Bio::Locations.new(location.to_s).span

    :mismatch unless span == [1, length]
  rescue StandardError
    :unreadable
  end
end
