class RegenerateSubmissionFlatfilesJob < ApplicationJob
  include SubmissionOutputWriter

  # The failure is written down before it is re-raised: which submission,
  # and what went wrong, in words a curator can act on. Re-raised so the
  # queue still records a failed job and Sentry still sees it — the run
  # screen is where the failure is read, not where it is reported.
  rescue_from StandardError do |error|
    run        = arguments.find { it.is_a?(RegenerateFlatfilesRun) }
    submission = arguments.find { it.is_a?(Submission) }

    run&.record_failure!(submission, error)

    raise error
  end

  def perform(submission, user, run, date, force: false)
    # Detect v3 BEFORE parsing — v3 ddbj_records can be multi-GB and
    # V3::Parser is full-document (Oj.load on the whole blob). Eating
    # that allocation just to raise V3NotImplementedError would burn RAM
    # and IO with no value. The detector peeks 64KB of head bytes.
    record = submission.ddbj_record.open do |file|
      major, = DDBJRecord::SchemaVersionDetector.detect(file)
      file.rewind

      if major == '3'
        raise DDBJRecord::V3NotImplementedError,
              "Submission ##{submission.id}: flatfile regeneration not yet implemented for v3 records (Phase 6+)"
      end

      DDBJRecord.parse(file)
    end

    regenerating = force || changed?(submission, record)

    if regenerating
      submission.accessions.update_all(locus_date: date) if date

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

    # Counted apart, because the two outcomes answer different questions:
    # a run that skipped everything did nothing, and a run that
    # regenerated everything rewrote the lot. The old single `processed`
    # counter could not tell them apart, so turning the rewrite option
    # off produced a result nobody could read.
    run.count! regenerating ? :regenerated : :skipped
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
