# What is in a set. Adding and removing are each member's own to do —
# see SubmissionSetInclusion for why nobody can put somebody else's work here.
class SetSubmissionsController < ApplicationController
  include SetContents

  before_action :refuse_proxy!
  before_action :load_set

  # More than the list screen can show at once, and far less than a
  # runaway client. A page of the submitter's list is 20; somebody
  # pasting ten thousand ids is not doing what this is for.
  MAX_PER_CALL = 200

  # A list, always — one submission is a list of one. The submitter's
  # list screen adds a page's worth in a press, and doing that as N
  # requests would leave nobody holding the answer to "what actually went
  # in": a client that loses its connection halfway has added some of
  # them and cannot say which.
  def create
    # Read rather than `expect`ed: `expect` turns an empty list into a
    # bare 400 with Rails' own words, and "nothing was selected" is a
    # state a client can be in and deserves a sentence.
    raw = params[:submission_request_ids]

    refuse! 'No submissions were named.' unless raw.is_a?(Array) && raw.any?

    ids = raw.map(&:to_i).uniq

    refuse! "Too many at once — #{MAX_PER_CALL} is the maximum." if ids.size > MAX_PER_CALL

    # Scoped to what the caller owns, so an id they merely read through
    # another set 404s rather than being quietly dropped: from here,
    # somebody else's submission is not an id they have, and silently
    # adding fewer than they asked for is the worse answer.
    requests = current_user.submission_requests.where(id: ids)

    raise ActiveRecord::RecordNotFound, "Couldn't find SubmissionRequest with 'id'=#{(ids - requests.ids).first}" if requests.size != ids.size

    within_submission_set_membership(@set) do
      # Already there is not a failure. Ten checkboxes where three are
      # already in the set is an ordinary press, and refusing the lot —
      # which is what a unique index does — would make the submitter
      # work out which three and try again without them.
      already = @set.inclusions.where(submission_request_id: ids).pluck(:submission_request_id)
      fresh   = requests.to_a.reject { already.include?(it.id) }

      fresh.each do |request|
        @set.inclusions.create!(submission_request: request, added_by: current_user)
      end

      @added          = fresh.size
      @already_in_set = already.size
    end

    render :create
  end

  def destroy
    submission_set_inclusion = @set.inclusions.find_by!(submission_request_id: params.expect(:submission_request_id))

    unless submission_set_inclusion.submission_request.user_id == current_user.id
      forbid! 'Only the submission owner can take it out of a set.'
    end

    submission_set_inclusion.destroy!

    head :no_content
  end

  private

  def load_set
    @set = SubmissionSet.joined_by(current_user).find(params.expect(:set_id))
  end
end
