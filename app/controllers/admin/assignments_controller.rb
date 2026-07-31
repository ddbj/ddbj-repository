module Admin
  # "Assign to me" from the workbench summary bar — the one-click form of
  # the assignee field in the curation rail, put next to the primary
  # action because claiming a request is what a curator does before
  # working on it.
  class AssignmentsController < ApplicationController
    def create
      submission = Submission.find(params[:submission_id])

      CurationUpdate.new(
        submission:,
        actor:  "admin:#{current_user.uid}",
        params: {assignee_id: current_user.id.to_s}
      ).call

      redirect_to admin_submission_request_path(submission.request),
                  notice: "Assigned to #{current_user.uid}."
    rescue CurationUpdate::Refused => e
      redirect_to admin_submission_request_path(submission.request), alert: "Could not assign: #{e.message}"
    end
  end
end
