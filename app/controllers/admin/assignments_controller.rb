module Admin
  # "Assign to me" from the workbench summary bar and from My queue's
  # Unclaimed section — the one-click form of the assignee field in the
  # curation rail, put next to the primary action because claiming a
  # request is what a curator does before working on it.
  #
  # Addressed by request rather than by submission: assignment is a column
  # on the request now, and the requests most worth claiming are the ones
  # that have not been applied and so have no submission at all.
  class AssignmentsController < ApplicationController
    def create
      request = SubmissionRequest.find(params[:submission_request_id])

      request.assign!(current_user)

      # The event hangs off the submission (the audit trail's unit), so a
      # pre-Apply claim leaves no event — there is nothing yet to attach
      # it to. The request's own assignee column carries the fact.
      if request.submission
        CurationEvent.record!(
          submission: request.submission,
          actor:      current_actor,
          action:     :curation_updated,
          assignee:   current_user.uid
        )
      end

      redirect_to admin_submission_request_path(request), notice: "Assigned to #{current_user.uid}."
    rescue ArgumentError => e
      redirect_to admin_submission_request_path(request), alert: "Could not assign: #{e.message}"
    end
  end
end
