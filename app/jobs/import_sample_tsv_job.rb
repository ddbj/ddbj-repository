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
      error_report: "#{SampleTSVImport::ABORT_PREFIX}#{error.class}: #{error.message}"
    )

    # Discarding handles the job; it does not handle the bug. Without
    # this the exception reaches nobody — and the result screen tells the
    # curator developers were notified, which has to be true.
    Rails.error.report(error, handled: true, source: 'import_sample_tsv_job')
  end

  # Another run of this import has it (AdvisoryLock): wait for it to end,
  # since it may yet die without finishing. After `discard_on`, so it is
  # this that a held lock meets. Five minutes rather than one, since each
  # wait enqueues the TSV again — tens of MB.
  retry_on AdvisoryLock::Held, wait: 5.minutes, attempts: :unlimited

  # One run per import (AdvisoryLock): a job stopped part way is run again
  # from the start (RecoverKilledJobsJob) — the import is one transaction,
  # so nothing of it was written — and the run it replaces may be alive yet.
  # One that has ended is not run again.
  def perform(import_id:, tsv_body:)
    AdvisoryLock.exclusively "import_sample_tsv:#{import_id}" do
      progress = SampleTSVImport.find(import_id)

      import progress, tsv_body if progress.loading?
    end
  end

  private

  # One import a submission at a time — a second would race the chain —
  # and the curator who started it told so, rather than left to wonder.
  # Said by a lock, not by rows saying `running`: an import stopped with
  # its process leaves its row so, for good, and every later import would
  # be refused. Whoever holds the lock ends those — `running` ones only,
  # since a `queued` one is waiting for its job, not stopped.
  def import(progress, tsv_body)
    AdvisoryLock.exclusively "import_sample_tsv:submission:#{progress.submission_id}" do
      SampleTSVImport.where(submission_id: progress.submission_id, status: 'running').where.not(id: progress.id).find_each do |stopped|
        stopped.update!(status: 'failed', finished_at: Time.current, error_report: SampleTSVImport::STOPPED_MESSAGE)
      end

      progress.update! status: 'running'

      run progress, tsv_body
    end
  rescue AdvisoryLock::Held
    progress.update!(
      status:       'failed',
      finished_at:  Time.current,
      error_report: SampleTSVImport::CONFLICT_MESSAGE
    )
  end

  def run(progress, tsv_body)
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
