# Running the check again.
#
# The way out of a check that has gone stale, which is the one refusal
# `SubmissionRequest#send_blocked_reason` gives where nothing is wrong
# with the file — only the answer about it has expired. Without this the
# screen names a way out that has no control, and the submitter's only
# move is to abandon the request and upload the same file again.
#
# A check replaces its predecessor rather than joining it: `has_one` plus
# `create_validation!` has always meant that, and the unique index now
# says so.
class ValidationsController < ApplicationController
  before_action :refuse_proxy!

  def create
    request = current_user.submission_requests.find(params[:submission_request_id])

    # Not while one is already running, and not on a request that has been
    # put down or already handed over — `recheckable?` is the screen's
    # rule and this one, said once.
    #
    # Under a lock, so two presses cannot both find it checkable and check
    # it twice — the second finds it already waiting.
    request.with_lock do
      refuse! 'This request cannot be checked again.' unless request.recheckable?

      # Straight to the column, as the apply's own status is written: a
      # request whose validations no longer pass (its assignee stopped
      # being a curator) is still checked.
      request.update_columns status: 'waiting_validation', updated_at: Time.current
    end

    ValidateDDBJRecordJob.perform_later request

    head :no_content
  end
end
