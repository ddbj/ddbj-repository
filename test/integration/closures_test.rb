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

  # A closure says "I am not taking this further". Applying it anyway
  # would leave closed_at set through curation and release — and the
  # client reads closed_at before everything else, so a public record
  # would report itself as one the submitter had put down.
  test 'a closed request cannot be applied' do
    # Everything the apply endpoint asks for, so the refusal is the
    # closure and not a missing validation.
    @req.update_columns(status: SubmissionRequest.statuses.fetch('ready_to_apply'))
    Validation.create!(subject: @req, progress: :finished, finished_at: Time.current)
    @req.close!

    assert_no_difference 'Submission.count' do
      post submission_request_submission_path(@req)
    end

    assert_response :unprocessable_entity
    assert_predicate @req.reload, :closed?

    # And the same request applies once it is picked back up, so the
    # refusal is the closure rather than the setup.
    @req.reopen!

    post submission_request_submission_path(@req)

    assert_response :no_content
  end

  # Otherwise the mail goes out and the app shows nothing: a closed
  # request is not in "needs you", and counts as finished, so it is not
  # even in the list the submitter opens by default.
  test 'a curator asking something reopens what was put down' do
    @req.close!

    assert_difference 'SubmissionMessage.count', 1 do
      @req.messages.create!(user: users(:bob), author_role: :curator, body: 'one more thing')
      @req.reopen_if_closed!
    end

    assert_not_predicate @req.reload, :closed?
    assert_includes SubmissionRequest.needs_submitter_action, @req
  end

  # The admin ledger orders by updated_at — "what moved" — so a reopen
  # that reopens nothing must not float an untouched request to the top
  # of every curator's list.
  test 'reopening what is already open touches nothing' do
    # Dated back rather than compared to itself: a write lands within the
    # same second as the read, so second precision cannot tell "no write"
    # from "written just now".
    @req.update_columns(updated_at: 1.day.ago)
    before = @req.reload.updated_at

    delete submission_request_closure_path(@req)

    assert_response :success
    assert_equal before, @req.reload.updated_at
  end

  test 'somebody else request is not theirs to close' do
    other = submission_requests(:st26)
    other.update_columns(user_id: users(:bob).id, status: SubmissionRequest.statuses.fetch('validation_failed'))

    post submission_request_closure_path(other)

    assert_response :not_found
    assert_not_predicate other.reload, :closed?
  end
end
