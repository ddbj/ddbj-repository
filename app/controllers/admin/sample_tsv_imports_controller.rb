module Admin
  # Upload a TSV that applies to a BS submission's samples (see
  # SampleTSV::Importer for semantics). The upload is enqueued and the
  # curator polls #show until the SampleTSVImport row reaches a
  # terminal state.
  class SampleTSVImportsController < ApplicationController
    def show
      @submission = Submission.find(params[:submission_id])
      @import     = @submission.sample_tsv_imports.find(params[:id])
    end

    def create
      submission = Submission.find(params[:submission_id])
      uploaded   = params.require(:file)

      import = submission.sample_tsv_imports.create!(
        actor:      current_user.uid,
        started_at: Time.current
      )

      # `read` here materialises the upload into a String for the
      # background job. For 100K samples × ~30 cols that's tens of
      # megabytes — fine for a single SolidQueue payload. Once we hit
      # the actual Postgres bytea ceiling we'll move to ActiveStorage.
      ImportSampleTSVJob.perform_later(import_id: import.id, tsv_body: uploaded.read)

      redirect_to admin_submission_sample_tsv_import_path(submission, import),
                  notice: 'TSV upload accepted. The import is running in the background.'
    end

    def error_report
      submission = Submission.find(params[:submission_id])
      import     = submission.sample_tsv_imports.find(params[:id])

      unless import.error_report.present?
        return redirect_to admin_submission_sample_tsv_import_path(submission, import),
                           alert: 'No error report available.'
      end

      send_data import.error_report,
                type:     'text/tab-separated-values; charset=utf-8',
                filename: "submission-#{submission.id}-import-#{import.id}-errors.tsv"
    end
  end
end
