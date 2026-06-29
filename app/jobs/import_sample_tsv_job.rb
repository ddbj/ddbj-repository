# Runs SampleTSV::Importer against an uploaded TSV body and reports
# progress + error report on the supplied SampleTSVImport row.
#
# `tsv_body` rides through ActiveJob as a serialized String. For 100K
# samples × ~30 columns the body lands around 30-50 MB, well inside
# SolidQueue's payload tolerance. A future extension could move the
# body to ActiveStorage if uploads grow further.
class ImportSampleTSVJob < ApplicationJob
  # The Importer already records failure rows on the progress row. A
  # blanket retry would just re-run from scratch and never converge on
  # bad inputs (the curator has to fix the TSV); discard makes the
  # failure visible in the admin progress page and avoids
  # accumulating jobs.
  discard_on StandardError do |job, error|
    import_id = job_kwarg(job, :import_id)
    progress  = SampleTSVImport.find_by(id: import_id)
    progress&.update!(
      status:       'failed',
      finished_at:  Time.current,
      error_report: "Job aborted: #{error.class}: #{error.message}"
    )
  end

  # Best-effort accessor for a keyword argument off the job, tolerant
  # of ActiveJob's symbol-key serialization quirks and any future
  # adapter that round-trips kwargs as string-keyed hashes.
  def self.job_kwarg(job, name)
    arg = job.arguments.first
    return nil unless arg.is_a?(Hash)

    arg[name] || arg[name.to_s]
  end

  def perform(import_id:, tsv_body:)
    progress = SampleTSVImport.find(import_id)

    # Soft concurrency guard — same pattern as PublishBpXMLJob. A second
    # running import on the same submission would race the chain; mark
    # this attempt as failed and bail so the curator sees the conflict
    # in the progress page instead of silently appending overlapping
    # SubmissionUpdates.
    if SampleTSVImport.where(submission_id: progress.submission_id, status: 'running').where.not(id: progress.id).exists?
      progress.update!(
        status:       'failed',
        finished_at:  Time.current,
        error_report: 'Another sample TSV import is already running for this submission. Try again once it finishes.'
      )
      return
    end

    result = SampleTSV::Importer.new(
      submission: progress.submission,
      tsv_body:   tsv_body,
      actor:      "admin:#{progress.actor}"
    ).call

    progress.update!(
      status:       'completed',
      total:        result.total,
      processed:    result.processed,
      failed:       result.failed,
      error_report: result.error_report || result.fatal_error,
      finished_at:  Time.current
    )
  end
end
