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
      actor:      "admin:#{progress.actor}",
      progress:   Reporter.new(progress)
    ).call

    # A fatal result parsed nothing and wrote nothing, so it is a failure
    # however few rows it managed to look at. Recording it as `completed`
    # with 0 rejections made the screen read "Finished — every row
    # applied" over an import that never got past the header.
    progress.update!(
      status:       result.fatal_error ? 'failed' : 'completed',
      phase:        nil,
      total:        result.total,
      processed:    result.processed,
      failed:       result.failed,
      error_report: result.error_report || result.fatal_error,
      rejections:   result.rejections || [],
      finished_at:  Time.current
    )
  end

  # Writes the importer's two phases onto the row the screen polls.
  #
  # Checking counts rows because it can; applying says how many will be
  # written and stops there, because the write is one transaction and a
  # bar that implied otherwise would be describing work that does not
  # happen in that shape.
  class Reporter
    def initialize(import) = @import = import

    def checking(checked:, rejected:, total:)
      @import.update_columns(phase: 'checking', total:, processed: checked, failed: rejected,
                             updated_at: Time.current)
    end

    def applying(rows:)
      @import.update_columns(phase: 'applying', processed: rows, updated_at: Time.current)
    end
  end
end
