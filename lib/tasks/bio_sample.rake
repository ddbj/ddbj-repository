namespace :bio_sample do
  # Until 2026-09 a sample row could name its sample otherwise than the record
  # spells the alias (D-way's runs of spaces were kept in the row and
  # collapsed in the record), and what finds a sample's record by its row
  # missed it: a TSV import appended a second sample under the same alias,
  # and accession issuance never wrote the accession into the record. This
  # lists the records that happened to. It writes nothing but the record
  # cache materialising fills.
  desc 'List BioSample records holding a sample twice, or lacking an issued accession, from sample rows named unlike their alias'
  task audit_sample_names: :environment do
    name = ->(sample) { Sample.normalise_name(sample['alias']) }

    tsv_imported = SubmissionUpdate.where(db: 'biosample', source: :tsv_import).distinct.pluck(:submission_id)
    issued       = CurationEvent.where(action: :accession_issued).distinct.pluck(:submission_id)

    Submission.where(db: 'biosample', id: tsv_imported | issued).find_each do |submission|
      record  = submission.materialised_record or next
      samples = Array(record['samples'])

      twice = samples.map(&name).tally.select { _2 > 1 }.keys
      puts "#{submission.id}\t#{submission.source_id}\ttwice\t#{twice.join(', ')}" if twice.any?

      by_name = samples.index_by(&name)

      missing = submission.samples.where.not(accession: nil).reject {|row|
        by_name[Sample.normalise_name(row.sample_name)]&.[]('accession') == row.accession
      }
      puts "#{submission.id}\t#{submission.source_id}\taccession\t#{missing.map(&:accession).join(', ')}" if missing.any?
    rescue Submission::MaterialisationFailed => e
      puts "#{submission.id}\t#{submission.source_id}\tunreadable\t#{e.message}"
    end
  end
end
