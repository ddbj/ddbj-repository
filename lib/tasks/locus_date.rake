namespace :locus_date do
  desc 'Put entries.locus_date back to the date the publication operator chose (LIMIT=/AFTER=/ACCESSIONS=/EXCEPT= to scope, APPLY=1 to write)'
  task backfill: :environment do
    # `EXCEPT` is the one option worth reading twice. An entry whose date was
    # deliberately set to something other than what the operator first asked for
    # — PATENT-386's five, redated to 2026-08-13 — would otherwise be pulled
    # back to what its request said. The dry run prints every move, so read it.
    result = LocusDateBackfill.audit(
      limit:      ENV['LIMIT'],
      after:      ENV['AFTER'],
      accessions: ENV['ACCESSIONS'],
      except:     ENV['EXCEPT']
    )

    LocusDateBackfill.report result

    puts "\nscanned #{result.scanned} #{'submission'.pluralize(result.scanned)}."

    if result.changes.empty?
      puts 'Nothing to redate.'
    elsif ENV['APPLY'] == '1'
      LocusDateBackfill.apply!(result.changes).each { puts it }

      puts "\nRedated #{result.changes.size} #{'entry'.pluralize(result.changes.size)} across #{result.submissions.size} #{'submission'.pluralize(result.submissions.size)}."

      # Deliberately not regenerated here. The column is now right; whether the
      # published flatfiles should be rebuilt — and when — is a publication
      # decision, and rebuilding one rewrites every entry of its submission.
      puts 'The flatfiles are untouched: regenerate the ones that need republishing, keeping the existing LOCUS dates.'
    else
      puts "\nDry run. Re-run with APPLY=1 to redate #{result.changes.size} #{'entry'.pluralize(result.changes.size)}."
    end

    # A submission this could not read is not a submission that agrees. Findings
    # themselves exit 0 — they are the report.
    next if result.unexamined.empty?

    $stdout.flush

    abort "#{result.unexamined.size} #{'submission'.pluralize(result.unexamined.size)} could not be examined, so this is not a clean bill of health."
  end
end
