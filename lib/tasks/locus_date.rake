namespace :locus_date do
  desc 'Put entries.locus_date back to the date the publication operator chose (LIMIT=/AFTER=/ACCESSIONS= to scope, APPLY=1 to write)'
  task backfill: :environment do
    applying = ENV['APPLY'] == '1'
    redated  = 0
    seen     = Set.new
    scanned  = 0
    skipped  = []

    # Reported as each submission is dealt with, and written in the same pass:
    # a run over the archive that collected first would hold every change in
    # memory, and one that printed only at the end would say nothing about the
    # 300 submissions it had already committed when the 301st raised.
    LocusDateBackfill.each_submission(limit: ENV['LIMIT'], after: ENV['AFTER'], accessions: ENV['ACCESSIONS']) do |outcome|
      scanned += 1
      seen.merge outcome.submission.entries.pluck(:accession)

      LocusDateBackfill.describe(outcome).each { puts it }

      skipped << outcome unless outcome.examined?

      next unless applying && outcome.changes.any?

      redated += LocusDateBackfill.apply!(outcome.changes)
    end

    puts "\nscanned #{scanned} #{'submission'.pluralize(scanned)}."

    if applying
      puts "Redated #{redated} #{'entry'.pluralize(redated)}."

      # Deliberately not regenerated. The column is now right, and the published
      # flatfiles already print these dates — they were only ever wrong in the
      # column. Regenerating is a publication decision, and it rewrites every
      # entry of a submission.
      puts 'The flatfiles are untouched, and now agree with the column.' if redated.positive?
    else
      puts 'Re-run with APPLY=1 to write.'
    end

    unmatched = LocusDateBackfill.unmatched(ENV['ACCESSIONS'], seen)

    problems = [
      ("#{unmatched.size} #{'accession'.pluralize(unmatched.size)} matched no ST.26 entry: #{unmatched.to_a.join(', ')}" if unmatched.any?),
      ("#{skipped.size} #{'submission'.pluralize(skipped.size)} could not be examined" if skipped.any?)
    ].compact

    next if problems.empty?

    # Neither is a clean bill of health: one is most likely a typo, the other is
    # a submission this run has said nothing about.
    $stdout.flush

    abort problems.join('. ') << '.'
  end
end
