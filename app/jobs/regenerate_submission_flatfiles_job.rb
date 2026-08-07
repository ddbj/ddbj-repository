class RegenerateSubmissionFlatfilesJob < ApplicationJob
  include SubmissionOutputWriter

  # The failure is written down before it is re-raised: which submission,
  # and what went wrong, in words a curator can act on. Re-raised so the
  # queue still records a failed job and Sentry still sees it — the run
  # screen is where the failure is read, not where it is reported.
  rescue_from StandardError do |error|
    run, submission, label = failed_target

    run&.record_failure!(submission, error, label:)

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
      submission.entries.update_all(locus_date: date) if date

      rows                = submission.entries.reload.to_a
      entries             = build_entries(record, rows)
      record_with_entries = record.with(sequences: record.sequences.with(entries:))

      generate_outputs record_with_entries, entries, **{
        filename:       submission.ddbj_record.filename,
        content_type:   submission.ddbj_record.content_type,
        flatfile_omits: retracted_entry_ids(rows)
      } do |updates|
        submission.update! updates
      end

      EntryHistory.insert_all! submission.entries.ids.map {|id|
        {
          entry_id: id,
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
    run.count! (regenerating ? :regenerated : :skipped), submission
  end

  private

  # Which run to report to, and which submission the report is about.
  #
  # A submission destroyed between enqueue and execution makes reading
  # the job's own arguments the thing that fails, and `arguments` is
  # then simply empty — it does not raise, it reports nothing. Read only
  # from there, the handler would find no run, so the failure would go
  # unrecorded, the run would never reach its total, and the screen
  # would sit at "Regenerating…" until the stale bound caught it an hour
  # later. The serialised form still names both.
  def failed_target
    run        = arguments.find { it.is_a?(RegenerateFlatfilesRun) } || locate_serialized(RegenerateFlatfilesRun)
    submission = arguments.find { it.is_a?(Submission) }

    [run, submission, ("#{serialized_label(Submission)} (deleted)" unless submission)]
  end

  def serialized_globalid(klass)
    serialized_arguments
      .grep(Hash)
      .filter_map { it['_aj_globalid'] }
      .find { it.include?("/#{klass.name}/") }
  end

  def locate_serialized(klass)
    gid = serialized_globalid(klass) or return nil

    GlobalID::Locator.locate(gid)
  rescue ActiveRecord::RecordNotFound
    # The run itself has been deleted. There is nowhere to report to,
    # and raising here would replace the failure with one about it.
    nil
  end

  def serialized_label(klass)
    gid = serialized_globalid(klass)

    gid ? "#{klass.name.underscore.humanize} ##{gid.split('/').last}" : 'unknown submission'
  end

  def changed?(submission, record)
    # `reload`, because the caller may have loaded the association before
    # handing the submission over — a second run in the same process
    # otherwise compares against the statuses of the first, and a
    # retraction that changed the flatfile is reported as no change.
    rows                = submission.entries.reload.to_a
    entries             = build_entries(record, rows)
    record_with_entries = record.with(sequences: record.sequences.with(entries:))

    result = false

    generate_outputs record_with_entries, entries, **{
      filename:       submission.ddbj_record.filename,
      content_type:   submission.ddbj_record.content_type,
      flatfile_omits: retracted_entry_ids(rows)
    } do |updates|
      result =
        attachment_changed?(submission.ddbj_record, updates[:ddbj_record]) ||
        attachment_changed?(submission.flatfile_na, updates[:flatfile_na]) ||
        attachment_changed?(submission.flatfile_aa, updates[:flatfile_aa])
    end

    result
  end

  # Retracting an entry changes the flatfile, so this is also what makes
  # `changed?` notice and regenerate rather than skip.
  def retracted_entry_ids(rows) = rows.select(&:retracted?).map(&:entry_id).to_set

  def build_entries(record, rows)
    rows_by_entry_id = rows.index_by(&:entry_id)

    record.sequences.entries.map {|entry|
      acc = rows_by_entry_id.fetch(entry.id)

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
