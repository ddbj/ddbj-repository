class RegenerateSubmissionFlatfilesJob < ApplicationJob
  include SubmissionOutputWriter

  def perform(submission, user, progress)
    record                 = submission.ddbj_record.open { DDBJRecord.parse(it) }
    accessions_by_entry_id = submission.accessions.index_by(&:entry_id)

    entries = record.sequences.entries.map {|entry|
      acc = accessions_by_entry_id.fetch(entry.id)

      entry.with(
        accession:    acc.number,
        locus:        acc.number,
        version:      acc.version,
        last_updated: acc.locus_date.to_s
      )
    }

    record = record.with(sequences: record.sequences.with(entries:))

    generate_outputs record, entries, **{
      filename:     submission.ddbj_record.filename,
      content_type: submission.ddbj_record.content_type
    } do |updates|
      submission.update! updates
    end

    AccessionHistory.insert_all! submission.accessions.ids.map {|id|
      {
        accession_id: id,
        user_id:      user.id,
        action:       'regenerate'
      }
    }

    progress.increment! :processed
  end
end
