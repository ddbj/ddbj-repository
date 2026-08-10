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
      scope   = ST26SourceLocations.scope(ENV['ACCESSIONS'])
      findings = ST26SourceLocations.audit(scope) {|submission| warn "  scanning submission ##{submission.id}" if ENV['VERBOSE'] }

      ST26SourceLocations.report findings

      # Counted in locations rather than entries: an entry can carry more than
      # one source feature, and the correction is applied per location.
      puts findings.empty? ? 'OK: every source location spans its sequence.' : "#{findings.size} disagreeing #{'location'.pluralize(findings.size)}."
    end

    desc 'Rewrite disagreeing source locations to 1..<length> (ACCESSIONS= required, APPLY=1 to write)'
    task fix: :environment do
      accessions = ENV['ACCESSIONS'].to_s

      # A blanket rewrite is refused. The correction is only ever right for
      # records already known to be wrong, and the audit is how they become
      # known — a bare `rake st26:source_locations:fix` would otherwise rewrite
      # the archive on the strength of a typo.
      abort 'ACCESSIONS is required: name the accessions to correct, comma or space separated.' if accessions.blank?

      scope    = ST26SourceLocations.scope(accessions)
      findings = ST26SourceLocations.audit(scope)

      ST26SourceLocations.report findings

      if findings.empty?
        puts 'Nothing to correct.'
        next
      end

      unless ENV['APPLY'] == '1'
        puts "\nDry run. Re-run with APPLY=1 to rewrite #{findings.size} location(s)."
        next
      end

      ST26SourceLocations.correct! findings

      remaining = ST26SourceLocations.audit(ST26SourceLocations.scope(accessions))

      if remaining.empty?
        puts "\nCorrected. Every source location in scope now spans its sequence."
        puts 'The flatfiles still hold the old spans — regenerate them from Admin → Regenerate flatfiles for these accessions.'
      else
        ST26SourceLocations.report remaining
        abort "#{remaining.size} location(s) still disagree after the rewrite."
      end
    end
  end
end

# Rake tasks are not a place to keep logic, but this is a one-off correction
# rather than a feature: putting it in app/ would leave a class behind that
# nothing calls once the five records are fixed. It lives here so it can be
# deleted with the tasks that use it.
module ST26SourceLocations
  Finding = Data.define(:submission, :accession, :entry_id, :source_id, :location, :expected)

  module_function

  def scope(accessions)
    base  = Submission.st26_db.where.associated(:ddbj_record_attachment)
    names = accessions.to_s.split(/[\s,]+/).reject(&:blank?)

    return base if names.empty?

    base.where(id: Entry.where(accession: names).select(:submission_id))
  end

  # Reads the record the way the flatfile renderer does — through the parser,
  # not the raw JSON — so a finding here is a finding the renderer would act
  # on. Streams, because `scope` with no accessions is every ST.26 submission.
  def audit(scope)
    scope.find_each.flat_map {|submission|
      yield submission if block_given?

      accessions = submission.entries.pluck(:entry_id, :accession).to_h

      each_source_location(submission).filter_map {|entry_id, source_id, location, length|
        expected = "1..#{length}"

        next if span_matches?(location, length)

        Finding.new(
          submission:,
          accession:  accessions[entry_id],
          entry_id:,
          source_id:,
          location:,
          expected:
        )
      }
    }
  end

  def report(findings)
    return if findings.empty?

    findings.each do |f|
      puts format(
        '%-12s submission #%-6d %-40s %-16s -> %s',
        f.accession || '(no accession)',
        f.submission.id,
        f.entry_id,
        f.location,
        f.expected
      )
    end
  end

  # Rewrites the stored record in place. The raw JSON is mutated rather than
  # re-serialised from the parsed Data objects: the blob is the archived
  # record, and a round trip through the parser would rewrite fields this
  # correction has no business touching.
  def correct!(findings)
    findings.group_by(&:submission).each do |submission, group|
      wanted = group.to_h { [[it.entry_id, it.source_id], it.expected] }

      json = submission.ddbj_record.open { Oj.load(it.read, mode: :strict) }

      rewritten = 0

      Array(json.dig('sequences', 'entries')).each do |entry|
        Array(entry['source_features']).each do |sf|
          expected = wanted[[entry['id'], sf['id']]] or next

          sf['location'] = expected
          rewritten     += 1
        end
      end

      raise "submission ##{submission.id}: expected to rewrite #{group.size} location(s), rewrote #{rewritten}" unless rewritten == group.size

      submission.ddbj_record.attach(
        io:           StringIO.new(Oj.dump(json, mode: :strict)),
        filename:     submission.ddbj_record.filename.to_s,
        content_type: submission.ddbj_record.content_type
      )

      puts "submission ##{submission.id}: rewrote #{rewritten} location(s)"
    end
  end

  def each_source_location(submission)
    return enum_for(:each_source_location, submission) unless block_given?

    submission.ddbj_record.open do |file|
      major, = DDBJRecord::SchemaVersionDetector.detect(file)
      file.rewind

      # v3 entries carry no `length`, and no v3 record reaches the flatfile
      # renderer yet. Named rather than skipped silently.
      if major == '3'
        warn "submission ##{submission.id}: skipped, v3 record"
        next
      end

      DDBJRecord::StreamingParser.new(file.path).each_entry do |entry|
        length = entry.length.to_i

        next unless length.positive?

        Array(entry.source_features).each do |sf|
          yield entry.id, sf.id, sf.location, length
        end
      end
    end
  end

  def span_matches?(location, length)
    Bio::Locations.new(location.to_s).span == [1, length]
  rescue StandardError
    false
  end
end
