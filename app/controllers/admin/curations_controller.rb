module Admin
  # The curation rail on the workbench Overview: status, assignee, hold
  # date and the internal comment save as one decision. The fan-out across
  # typed columns, the patch chain and the projected hold-date column
  # lives in CurationUpdate.
  class CurationsController < ApplicationController
    def update
      submission = Submission.find(params[:submission_id])

      result = CurationUpdate.new(
        submission:,
        actor:  "admin:#{current_user.uid}",
        params: curation_params
      ).call

      participate!(submission.request) if result.any?

      notice = result.any? ? "Saved #{result.to_sentence}." : 'Nothing changed.'

      redirect_to admin_submission_request_path(submission.request), notice:
    rescue CurationUpdate::Refused, ActiveRecord::RecordInvalid => e
      redirect_to admin_submission_request_path(submission.request), alert: "Could not save: #{e.message}"
    rescue Submission::MaterialisationFailed => e
      redirect_to admin_submission_request_path(submission.request),
                  alert: "Cannot edit: existing patch chain is unreadable (#{e.class}: #{e.message})."
    end

    private

    # Only the keys the form actually rendered arrive here — the hold-date
    # input is omitted entirely when the chain cannot be replayed, and
    # CurationUpdate reads absence as "leave alone".
    def curation_params
      params.fetch(:curation, {}).permit(:status, :assignee_id, :hold_date, :curator_comment)
    end
  end
end
