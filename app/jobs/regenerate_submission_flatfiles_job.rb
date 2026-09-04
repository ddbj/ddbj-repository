class RegenerateSubmissionFlatfilesJob < ApplicationJob
  include SubmissionOutputWriter

  # The failure is written down before it is re-raised: which submission,
  # and what went wrong, in words a curator can act on. Re-raised so the
  # queue still records a failed job and Sentry still sees it — the run
  # screen is where the failure is read, not where it is reported.
  # Not a bare RuntimeError: a pre-backfill run over the archive would otherwise
  # produce thousands of failure rows indistinguishable from a bug, and this one
  # means "not ready" rather than "broken".
  class LocusDateDisagreement < StandardError; end

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

    entries             = build_entries(record, rows, redated:)
    record_with_entries = record.with(sequences: record.sequences.with(entries:))

    regenerated = false

    generate_outputs record_with_entries, entries, **{
      filename:       submission.ddbj_record.filename,
      content_type:   submission.ddbj_record.content_type,
      flatfile_omits: retracted_entry_ids(rows)
    } do |outputs|
      # Written once, from the outputs the comparison was made against.
      # Generating a second time to write what was just compared doubled
      # the cost of every submission a run actually changed — which, on
      # the runs this tool exists for, is all of them.
      next unless changed?(submission, outputs)

      # The dates, the attachments that print them, and the history, in one
      # commit — and the bytes uploaded before it opens. Written apart, a job
      # that died between them left a flatfile saying one date and the row
      # behind it saying another, and the next run would read the file as
      # already correct, generate the same bytes, and skip, so the two would
      # never be brought back together. `write_outputs!` is where the upload
      # ordering lives, so ApplySubmissionRequestJob gets it too.
      write_outputs! submission, outputs do
        # By id when the run named accessions, and by submission when it
        # did not — the whole-submission case would otherwise send every
        # entry id back as an IN list.
        (accessions ? Entry.where(id: redated.map(&:id)) : submission.entries).update_all(locus_date: date) if date

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

  def read_record(submission)
    submission.ddbj_record.open do |file|
      # The flatfile renderer is v2-shaped, so a v3 record cannot be
      # regenerated. Refused before the body is read.
      DDBJRecord.refuse_v3! file, "Submission ##{submission.id}"

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
  def changed?(submission, outputs)
    attachment_changed?(submission.ddbj_record, outputs[:ddbj_record]) ||
      attachment_changed?(submission.flatfile_na, outputs[:flatfile_na]) ||
      attachment_changed?(submission.flatfile_aa, outputs[:flatfile_aa])
  end

  # Retracting an entry changes the flatfile, so this is also what makes
  # `changed?` notice and regenerate rather than skip.
  def retracted_entry_ids(rows) = rows.select(&:retracted?).map(&:entry_id).to_set

  def build_entries(record, rows, redated: [])
    rows_by_entry_id = rows.index_by(&:entry_id)
    dated            = redated.to_set

    record.sequences.entries.map {|entry|
      acc = rows_by_entry_id.fetch(entry.id)

      # An entry this run is dating takes the run's date; the rest are rendered
      # from the column, and for those the column has to already agree with the
      # record. It does not on any submission applied before the apply job
      # started taking the date from the record: those hold the operator's date
      # in the record and the apply date in the column, so rendering from the
      # column moves the printed date. That is how 62 entries lost their
      # published dates while PATENT-386 was being fixed, and a comment saying
      # "run the backfill first" is not what stops it happening again.
      #
      # Refused per submission. `rescue_from` turns it into a failure row, so a
      # run reports exactly which submissions are not ready and rewrites none of
      # them.
      #
      # A record with no date at all is nothing to compare against, so it
      # passes. That is also what makes the old-name fallback in
      # DDBJRecord::Builders worth keeping rather than merely harmless: without
      # it every pre-rename record would arrive here blank, and the ~18,000
      # submissions this guard was written for would stop being compared. The
      # comment there says when the fallback can go. Refusing a blank instead is
      # not an option — the only escape below is naming the accession with a
      # date, and a run carries one date for all of them.
      unless dated.include?(acc) || entry.locus_date.blank? || entry.locus_date == acc.locus_date.to_s
        raise LocusDateDisagreement,
              "Submission ##{acc.submission_id}: #{entry.id} has LOCUS date #{entry.locus_date} in its record and " \
              "#{acc.locus_date} in entries.locus_date. Regenerating would publish the latter. " \
              'If the column is the date you meant, name this accession and that date on the Regenerate ' \
              'flatfiles tool and it will be written to both — naming accessions is what that screen is for, ' \
              'and no other screen can. ' \
              'If you have not touched it, something has written the column without the record — the two are ' \
              'kept together by the apply job and by this one, so find out what did before regenerating.'
      end

      entry.with(
        accession:  acc.accession,
        locus:      acc.accession,
        version:    acc.version,
        locus_date: acc.locus_date.to_s
      )
    }
  end

  def attachment_changed?(attachment, output)
    if output.nil?
      attachment.attached?
    elsif attachment.attached?
      Digest::MD5.file(output[:io].path).base64digest != attachment.blob.checksum
    else
      true
    end
  end
end
