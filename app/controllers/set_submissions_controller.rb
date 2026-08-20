# What is in a set. Adding and removing are each member's own to do —
# see SubmissionSetInclusion for why nobody can put somebody else's work here.
class SetSubmissionsController < ApplicationController
  include SetContents

  before_action :refuse_proxy!
  before_action :load_set

  def create
    # Scoped to what the caller owns, so a request they merely read
    # through another set 404s rather than being quietly refused: from
    # here, somebody else's submission is not an id they have.
    request = current_user.submission_requests.find(params.expect(submission: [:submission_request_id])[:submission_request_id])

    within_submission_set_membership(@set) do
      @set.inclusions.create!(submission_request: request, added_by: current_user)
    end

    # Nothing back. Answering with the whole set would mean loading a
    # page of it — progress bar, accession summary and curation state per
    # row — on every add, for a body the client re-reads anyway.
    #
    # 204 rather than 201, even though this creates something: 204 is the
    # status that says "no body", and the web client's fetch layer treats
    # every other status as having one — a 201 with an empty body reaches
    # it as a JSON parse error, which is how this shipped broken. Every
    # other bodiless answer in this application is a 204 for the same
    # reason.
    head :no_content
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
