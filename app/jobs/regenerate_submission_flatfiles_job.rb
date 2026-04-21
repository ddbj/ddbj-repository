class RegenerateSubmissionFlatfilesJob < ApplicationJob
  include SubmissionOutputWriter

  def perform(submission, user, progress, date)
    record = submission.ddbj_record.open { DDBJRecord.parse(it) }

    if changed?(submission, record)
      submission.accessions.update_all locus_date: date

      entries             = build_entries(record, submission.accessions.reload)
      record_with_entries = record.with(sequences: record.sequences.with(entries:))

      generate_outputs record_with_entries, entries, **{
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
    end

    progress.increment! :processed
  end

  private

  def changed?(submission, record)
    entries             = build_entries(record, submission.accessions)
    record_with_entries = record.with(sequences: record.sequences.with(entries:))

    result = false

    generate_outputs record_with_entries, entries, **{
      filename:     submission.ddbj_record.filename,
      content_type: submission.ddbj_record.content_type
    } do |updates|
      result =
        attachment_changed?(submission.ddbj_record, updates[:ddbj_record]) ||
        attachment_changed?(submission.flatfile_na, updates[:flatfile_na]) ||
        attachment_changed?(submission.flatfile_aa, updates[:flatfile_aa])
    end

    result
  end

  def build_entries(record, accessions)
    accessions_by_entry_id = accessions.index_by(&:entry_id)

    record.sequences.entries.map {|entry|
      acc = accessions_by_entry_id.fetch(entry.id)

      entry.with(
        accession:    acc.number,
        locus:        acc.number,
        version:      acc.version,
        last_updated: acc.locus_date.to_s
      )
    }
  end

  def attachment_changed?(attachment, payload)
    if payload.nil?
      attachment.attached?
    elsif attachment.attached?
      Digest::MD5.file(payload[:io].path).base64digest != attachment.blob.checksum
    else
      true
    end
  end
end
