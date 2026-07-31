require 'test_helper'

# Putting a request down and picking it up again.
#
# A failed validation cannot be advanced — a corrected file arrives as a
# new request with no link back — so an abandoned attempt asked to be
# dealt with for ever, and the list's "needs you" ordering floats exactly
# those to the top. Closing is the only end such a request can reach.
class ClosuresTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"

    @req = submission_requests(:bioproject) # owned by :alice

    # What a failed validation actually looks like: the upload is there,
    # nothing was applied, so there is no submission behind it. The
    # fixture ships the opposite, and the payload is schema-checked.
    attach_ddbj_record(@req)
    @req.update_columns(status: SubmissionRequest.statuses.fetch('validation_failed'), submission_id: nil)
  end

  test 'closing takes it out of the queue without losing what happened' do
    assert_includes SubmissionRequest.needs_submitter_action, @req

    post submission_request_closure_path(@req)

    assert_conform_schema 200
    assert_not_nil response.parsed_body['closed_at']

    @req.reload

    assert_predicate @req, :closed?
    assert_equal 'validation_failed', @req.status, 'what happened is not overwritten by what was decided'

    assert_not_includes SubmissionRequest.needs_submitter_action, @req
    assert_includes     SubmissionRequest.finished, @req, 'it ends up somewhere, rather than vanishing'
  end

  test 'reopening is as cheap as closing' do
    @req.close!

    delete submission_request_closure_path(@req)

    assert_conform_schema 200
    assert_nil response.parsed_body['closed_at']
    assert_includes SubmissionRequest.needs_submitter_action, @req.reload
  end

  # "What is asking for something can be put down." A request being
  # validated is in flight, and an applied one has a submission whose end
  # the curator declares — a second notion of closed on the request would
  # put the same fact in two places.
  test 'a request that is not asking for anything cannot be closed' do
    @req.update_column(:status, SubmissionRequest.statuses.fetch('applied'))

    post submission_request_closure_path(@req)

    assert_response :unprocessable_entity
    assert_not_predicate @req.reload, :closed?
  end

  test 'closable says whether the button is offered' do
    get submission_request_path(@req)

    assert_conform_schema 200
    assert_equal true, response.parsed_body['closable']

    @req.update_column(:status, SubmissionRequest.statuses.fetch('validating'))
    get submission_request_path(@req)

    assert_equal false, response.parsed_body['closable']
  end

  test 'somebody else request is not theirs to close' do
    other = submission_requests(:st26)
    other.update_columns(user_id: users(:bob).id, status: SubmissionRequest.statuses.fetch('validation_failed'))

    post submission_request_closure_path(other)

    assert_response :not_found
    assert_not_predicate other.reload, :closed?
  end
end
