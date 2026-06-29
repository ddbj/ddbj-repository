module Admin
  # Download a BS submission's samples (typed columns + v3 attribute
  # bag) as a TSV. Read path only — there is no model row here, just a
  # streamed file response. See SampleTSV::Exporter for the column
  # layout and SampleTSVImportsController for the round-trip upload.
  class SampleTSVExportsController < ApplicationController
    def show
      submission = Submission.find(params[:submission_id])

      filename = "submission-#{submission.id}-samples.tsv"

      response.headers['Content-Type']        = 'text/tab-separated-values; charset=utf-8'
      response.headers['Content-Disposition'] = ActionDispatch::Http::ContentDisposition.format(disposition: 'attachment', filename:)

      self.response_body = SampleTSV::Exporter.new(submission).each
    end
  end
end
