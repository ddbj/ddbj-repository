namespace :st26 do
  namespace :source_locations do
    # INSDC-3468 / PATENT-386. JPO ST.26 files carried source feature locations
    # taken verbatim from the XML, which disagreed with the sequence in both
    # directions — three of the five records run one base past the end
    # (`1..449` over 448) and two stop short (`1..315` over 316). The flatfile
    # prints LOCUS from the length and both the source location and the
    # REFERENCE span from the location, so those records ship claiming two
    # different lengths.
    #
    # submission-bulk-st26 now pins the location to 1..<length> as it builds the
    # record (PAT_R0024), so this is only for the records that landed before it
    # did. The check stays there rather than being duplicated here: ST.26 is the
    # only database whose source is expected to be full length, the client is
    # where ST.26 records are made, and elsewhere a source may legitimately
    # cover part of an entry — a qualifier can even lift the expectation that
    # other features sit inside it.

    desc 'Report ST.26 entries whose source location disagrees with the sequence length (ACCESSIONS= to scope)'
    task audit: :environment do
      result = St26SourceLocations.audit(ENV['ACCESSIONS'])

      St26SourceLocations.report result

      # An accession that matched nothing counts here too: it is a question
      # this run did not answer, exactly like a record it could not read, and
      # the most likely reason for one is a typo in the list.
      unexamined = result.unreadable.size + result.skipped.size + result.unmatched.size

      if result.findings.any?
        puts "#{result.findings.size} #{'disagreement'.pluralize(result.findings.size)}."
      elsif unexamined.zero?
        puts 'OK: every source location spans its sequence.'
      end

      # A record that was not examined is not a record that is clean, and the
      # distinction has to survive being reduced to an exit status: anything
      # reading the tail of this output would otherwise take an unreadable or
      # skipped archive for a clean one. Findings themselves exit 0 — they are
      # the report this task exists to produce.
      #
      # Flushed first because `abort` writes to stderr, which is unbuffered:
      # a redirected run would otherwise show this line before the report it
      # is talking about.
      if unexamined.positive?
        $stdout.flush

        abort "#{unexamined} #{'thing'.pluralize(unexamined)} could not be examined, so this is not a clean bill of health."
      end
    end

    desc 'Set plain source locations to 1..<length> (ACCESSIONS= required, INCLUDE=short to also lengthen, APPLY=1 to write)'
    task fix: :environment do
      accessions = ENV['ACCESSIONS'].to_s

      # A blanket rewrite is refused. The correction is only ever right for
      # records already known to be wrong, and the audit is how they become
      # known — a bare `rake st26:source_locations:fix` would otherwise rewrite
      # the archive on the strength of a typo.
      #
      # Gated on the parsed list and not on the string: `ACCESSIONS=","` is not
      # `blank?` but parses to nothing, so `ACCESSIONS="$LIST," APPLY=1` with
      # `$LIST` unset used to run unscoped and rewrite every overrun in the
      # archive — the exact thing this guard is here to prevent. Checked before
      # the audit, so that case does not first stream the whole archive out of
      # object storage only to be refused.
      abort 'ACCESSIONS is required: name the accessions to correct, comma or space separated.' if St26SourceLocations.requested_from(accessions).empty?

      result = St26SourceLocations.audit(accessions)

      St26SourceLocations.report result

      # Only what was named, and only the reasons this run is allowed to act on.
      # Resolving accessions reaches whole submissions — a JPO request can carry
      # sixty entries — so without the first restriction, naming one accession
      # would rewrite every disagreeing sibling alongside it.
      allowed = St26SourceLocations.actionable_reasons(ENV['INCLUDE'])
      act     = ->(f) { allowed.include?(f.reason) }

      correctable, rest = result.named.partition(&act)

      # Named by reason. Both are refusals, but they are refusals to answer
      # different questions, and "unreadable" said of a length disagreement
      # sends the reader looking for a malformed location that is not there.
      rest.group_by(&:reason).each do |reason, group|
        puts "\n#{St26SourceLocations::REFUSALS.fetch(reason).call(group.size)} Fix #{group.size == 1 ? 'it' : 'them'} by hand."
      end

      abort "#{result.unmatched.size} #{'accession'.pluralize(result.unmatched.size)} matched no ST.26 entry — nothing was written." if result.unmatched.any?

      # A named record that could not be read is not a record that needs
      # nothing: its finding never got as far as being one, so without this the
      # task would print "Nothing to correct." over a missing blob.
      unexamined = result.unreadable.size + result.skipped.size

      abort "#{unexamined} named #{'submission'.pluralize(unexamined)} could not be examined — nothing was written." if unexamined.positive?

      if correctable.empty?
        puts 'Nothing to correct.'
        next
      end

      unless ENV['APPLY'] == '1'
        puts "\nDry run. Re-run with APPLY=1 to rewrite #{correctable.size} #{'location'.pluralize(correctable.size)}."
        next
      end

      St26SourceLocations.correct! correctable

      after     = St26SourceLocations.audit(accessions)
      remaining = after.named

      # The re-audit has to have *examined* what it is pronouncing on. A record
      # that could not be re-read lands in `unreadable`, which would leave
      # `remaining` empty and this check trivially satisfied — reporting the
      # rewrite as verified on the strength of not having looked. The
      # pre-checks above refuse the same situation for the same reason.
      unless remaining.none?(&act) && after.unreadable.empty? && after.skipped.empty?
        St26SourceLocations.report after

        abort 'The rewrite could not be confirmed: run the audit again.'
      end

      # Says what was written rather than that everything is now well: the
      # refused set is still wrong, and claiming otherwise on the line right
      # after refusing it is how a known problem gets forgotten.
      puts "\nRewrote #{correctable.size} #{'location'.pluralize(correctable.size)}."
      puts "#{remaining.size} named #{'location'.pluralize(remaining.size)} still #{remaining.size == 1 ? 'needs' : 'need'} fixing by hand." if remaining.any?
      puts 'The flatfiles still hold the old spans — regenerate them from Admin → Regenerate flatfiles for these accessions.'

      # The request keeps the file as it arrived, which is the point of it —
      # but that makes it disagree with the corrected submission, and it is
      # downloadable from both the admin screen and the API.
      puts "The submitter's uploaded copy on the request is deliberately left as received, so it still shows the old spans."
    end
  end
end
