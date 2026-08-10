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

  # `accessions` names the entries `date` is written to; nil writes it to
  # every entry of the submission.
  #
  # The file is the submission's — naming one accession still rewrites
  # the whole of the file that holds it — so the list decides only whose
  # date moves. A curator who lists numbers has already decided which
  # ones they are, and dating the rest of the file along with them would
  # move dates on records that merely share a submission.
  def perform(submission, user, run, date, accessions: nil)
    record = read_record(submission)

    # `reload`, because the caller may have loaded the association before
    # handing the submission over — a second run in the same process
    # otherwise reads the statuses and dates left by the first.
    rows    = submission.entries.reload.to_a
    named   = accessions&.to_set
    redated = date ? rows.select { named.nil? || named.include?(it.accession) } : []

    # Dated in memory first, so there is one account of what this run
    # means to write: the file is rendered from these rows and the UPDATE
    # below is made from the same ones. Entries left out keep the date
    # they have, so one file can carry two — which is what naming
    # accessions is for.
    redated.each { it.locus_date = date }

    entries             = build_entries(record, rows)
    record_with_entries = record.with(sequences: record.sequences.with(entries:))

    regenerated = false

    generate_outputs record_with_entries, entries, **{
      filename:       submission.ddbj_record.filename,
      content_type:   submission.ddbj_record.content_type,
      flatfile_omits: retracted_entry_ids(rows)
    } do |updates|
      # Written once, from the outputs the comparison was made against.
      # Generating a second time to write what was just compared doubled
      # the cost of every submission a run actually changed — which, on
      # the runs this tool exists for, is all of them.
      next unless changed?(submission, updates)

      # The dates, the attachments that print them, and the history, in
      # one commit. Written apart, a job that died between them left a
      # flatfile saying one date and the row behind it saying another —
      # and the next run would read the file as already correct, generate
      # the same bytes, and skip, so the two would never be brought back
      # together.
      #
      # The bytes are not in it: Active Storage defers the upload to
      # after_commit, so a storage failure still leaves rows pointing at
      # blobs that were never written — and the checksum on the row makes
      # the next run skip them. Submission#prime_cache! is the shape that
      # closes that (upload first, swap the pointer under the lock);
      # ApplySubmissionRequestJob writes its outputs the same way this
      # does, so it belongs in SubmissionOutputWriter rather than here.
      ActiveRecord::Base.transaction do
        # By id when the run named accessions, and by submission when it
        # did not — the whole-submission case would otherwise send every
        # entry id back as an IN list.
        (accessions ? Entry.where(id: redated.map(&:id)) : submission.entries).update_all(locus_date: date) if date

        submission.update! updates

        # Every entry of the submission, not only the redated ones: the
        # action is the rewrite of the file, and the file is theirs too.
        # Which dates moved is recorded on the run.
        EntryHistory.insert_all! rows.map {
          {
            entry_id: it.id,
            user_id:  user.id,
            action:   'regenerate'
          }
        }
      end

      regenerated = true
    end

    # Counted apart, because the two outcomes answer different questions:
    # a run that skipped everything did nothing, and a run that
    # regenerated everything rewrote the lot. The old single `processed`
    # counter could not tell them apart, so a run that changed nothing
    # produced a result nobody could read.
    run.count! (regenerated ? :regenerated : :skipped), submission
  end

  private

  # Detect v3 BEFORE parsing — v3 ddbj_records can be multi-GB and
  # V3::Parser is full-document (Oj.load on the whole blob). Eating that
  # allocation just to raise V3NotImplementedError would burn RAM and IO
  # with no value. The detector peeks 64KB of head bytes.
  def read_record(submission)
    submission.ddbj_record.open do |file|
      major, = DDBJRecord::SchemaVersionDetector.detect(file)
      file.rewind

      if major == '3'
        raise DDBJRecord::V3NotImplementedError,
              "Submission ##{submission.id}: flatfile regeneration not yet implemented for v3 records (Phase 6+)"
      end

      DDBJRecord.parse(file)
    end
  end

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

  # Whether writing these outputs would change anything. A run with
  # nothing to say about a submission leaves its blobs, and its history,
  # alone — a new date is a change like any other, and reaches here as
  # one, because the outputs were built with it already applied.
  def changed?(submission, updates)
    attachment_changed?(submission.ddbj_record, updates[:ddbj_record]) ||
      attachment_changed?(submission.flatfile_na, updates[:flatfile_na]) ||
      attachment_changed?(submission.flatfile_aa, updates[:flatfile_aa])
  end

  # Retracting an entry changes the flatfile, so this is also what makes
  # `changed?` notice and regenerate rather than skip.
  def retracted_entry_ids(rows) = rows.select(&:retracted?).map(&:entry_id).to_set

  def build_entries(record, rows)
    rows_by_entry_id = rows.index_by(&:entry_id)

    record.sequences.entries.map {|entry|
      acc = rows_by_entry_id.fetch(entry.id)

      entry.with(
        accession:    acc.accession,
        locus:        acc.accession,
        version:      acc.version,
        # From the column, which is the queryable copy of what the record
        # already says — equal by construction since the apply job started
        # taking the date from the record. Where they are not equal, the column
        # wins: it is what a curator's per-entry edit and this run's own date
        # option write to.
        locus_date: acc.locus_date.to_s
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
