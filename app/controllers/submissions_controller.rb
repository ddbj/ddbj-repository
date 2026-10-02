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
    # Found by ownership alone. Every other reason it cannot be sent is
    # asked of the record below and answered with a sentence: a request
    # that is closed, or unchecked, or checked too long ago, is one the
    # caller can see and is being refused — and 404 says the opposite of
    # that. It used to be a scope, and a check that had gone stale
    # overnight came back as "Not Found" against a request the screen was
    # still offering a button for.
    request = current_user.submission_requests.find(params[:submission_request_id])

    # Under a lock, so two presses cannot both find it sendable and send
    # it twice — the second finds it already waiting.
    request.with_lock do
      blocked = request.send_blocked_reason

      refuse! blocked if blocked

      # Straight to the column, as the apply writes its own: a request
      # whose validations no longer pass (its assignee stopped being a
      # curator) is still sent.
      request.update_columns status: 'waiting_application', updated_at: Time.current
    end

    ApplySubmissionRequestJob.perform_later request

    head :no_content
  end
end
