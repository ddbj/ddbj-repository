# Putting a request down, and picking it up again.
#
# A failed validation cannot be advanced — a corrected file arrives as a
# new request with no link back — so without this the attempt asks to be
# dealt with for ever, and the list's "needs you" ordering floats exactly
# those to the top. Only the submitter knows an attempt is abandoned:
# nothing in the data distinguishes one they mean to fix from one they
# have replaced.
#
# A closure records that decision beside the status rather than over it.
# `validation_failed` stays as the thing that happened.
class ClosuresController < ApplicationController
  before_action :set_request

  # Reopening is deliberately as cheap as closing. Closing costs nothing
  # and undoes nothing — the request keeps its validation, its messages
  # and its place in the history — so a misclick should not need a
  # curator to undo.
  def create
    unless @request.closable?
      return render json: {error: "A #{@request.status} request cannot be closed."},
                    status: :unprocessable_entity
    end

    @request.close!

    render 'submission_requests/show'
  end

  def destroy
    @request.reopen!

    render 'submission_requests/show'
  end

  private

  def set_request
    @request = current_user.submission_requests.find(params.expect(:submission_request_id))
  end
end
