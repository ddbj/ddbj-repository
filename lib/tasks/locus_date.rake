namespace :locus_date do
  desc 'Put entries.locus_date back to the date the publication operator chose (LIMIT=/AFTER=/ACCESSIONS= to scope, APPLY=1 to write)'
  task backfill: :environment do
    applying  = ENV['APPLY'] == '1'
    attention = []
    redated   = 0
    scanned   = 0
    seen      = Set.new

    # Reported as each submission is dealt with, and written in the same pass:
    # a run over the archive that collected first would hold every change in
    # memory, and one that printed only at the end would say nothing about the
    # 300 submissions it had already committed when the 301st raised.
    LocusDateBackfill.each_submission(limit: ENV['LIMIT'], after: ENV['AFTER'], accessions: ENV['ACCESSIONS']) do |outcome|
      scanned += 1

      # Only when there is a list to check against: on an archive-wide pass this
      # would be a query per submission for a set nothing reads.
      seen.merge outcome.submission.entries.pluck(:accession) if ENV['ACCESSIONS'].present?

      LocusDateBackfill.describe(outcome).each { puts it }

      attention << outcome if outcome.needs_attention?

      next unless applying && outcome.changes.any?

      redated += LocusDateBackfill.apply!(outcome.changes)
    end

    puts "\nscanned #{scanned} #{'submission'.pluralize(scanned)}."

    if applying
      puts "Redated #{redated} #{'entry'.pluralize(redated)}."

      # Deliberately not regenerated, and nothing needs to be: the published
      # flatfiles of these submissions already print the operator's date — it was
      # only ever the column that was wrong. (A submission whose file prints the
      # apply date has been regenerated, and this refuses those.)
      puts 'The flatfiles are untouched, and now agree with the column.' if redated.positive?
    else
      puts 'Re-run with APPLY=1 to write.'
    end

    unmatched = LocusDateBackfill.unmatched(ENV['ACCESSIONS'], seen)

    problems = [
      ("#{unmatched.size} #{'accession'.pluralize(unmatched.size)} matched no ST.26 entry: #{unmatched.to_a.join(', ')}" if unmatched.any?),
      ("#{attention.size} #{'submission'.pluralize(attention.size)} need attention rather than a backfill" if attention.any?)
    ].compact

    next if problems.empty?

    # Neither is a clean bill of health: one is most likely a typo, the other is
    # a submission this run has said nothing about.
    $stdout.flush

    abort problems.join('. ') << '.'
  end
end
