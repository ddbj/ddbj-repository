class SubmissionsController < ApplicationController
  include EnumFilterable

  def index
    scope = filter_by_enum(current_user.submissions, :db, params[:db], Submission.dbs.keys)

    @submissions = paginate(scope.order(id: :desc))
  end

  # Readable, not owned — following the request's own screen, which now
  # opens for a set's members. Nothing new is disclosed by it: what
  # this returns is the same `submission` object already embedded in the
  # request payload they can read. `index` above stays "mine", because a
  # list of my submissions is what it says it is.
  def show
    @submission = Submission.readable_by(current_user).find(params.expect(:id))
  end

  def create
    request = current_user.submission_requests.valid_only.joins(
      :validation
    ).where(
      validations: {
        finished_at: 1.day.ago..
      }
    ).find(params[:submission_request_id])

    # Closed means "not taking this further", and applying it anyway
    # would leave `closed_at` set through curation and release — where
    # the client reads it before everything else and would report a
    # public record as one the submitter had put down. Reopening first is
    # what the screen already tells them to do.
    raise ActiveRecord::RecordInvalid if request.closed?
    raise ActiveRecord::RecordInvalid unless request.ready_to_apply?

    request.waiting_application!

    ApplySubmissionRequestJob.perform_later request

    head :no_content
  end
end
