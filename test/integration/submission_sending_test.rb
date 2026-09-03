require 'test_helper'

# Whether "Send to DDBJ" can go through, and what is said when it cannot.
#
# The rule used to live in the endpoint's `find` scope, so a request whose
# check had gone stale overnight answered 404 — the same word as a request
# that was somebody else's — while the screen went on offering the button.
class SubmissionSendingTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @alice = users(:alice)

    default_headers['Authorization'] = "Bearer #{@alice.api_key}"

    # Straight to the column: `validates :ddbj_record, attached: true`
    # guards the submitter's upload flow and has nothing to say about a
    # status change made by a test.
    # `@req`, not `@request`: ApplicationSystemTestCase spells out why —
    # ActionDispatch::IntegrationTest replaces `@request` with its own
    # ActionDispatch::Request the moment one is performed, and a path
    # built from it afterwards names nothing, as a 404 rather than as an
    # error.
    @req = submission_requests(:st26)
    # No submission yet, which is what a request waiting to be sent is —
    # the fixture carries an applied one because most tests want that.
    @req.update_columns(
      status:        SubmissionRequest.statuses[:ready_to_apply],
      closed_at:     nil,
      submission_id: nil
    )

    attach_ddbj_record(@req)

    @validation = @req.validation || @req.create_validation!

    @validation.update!(progress: :finished, finished_at: Time.current)
    @validation.details.destroy_all
  end

  test 'a fresh check can be sent' do
    get submission_request_path(@req)

    assert_conform_schema 200
    assert_equal true, response.parsed_body['sendable']
    assert_nil response.parsed_body['send_blocked_reason']

    assert_enqueued_with job: ApplySubmissionRequestJob do
      post submission_request_submission_path(@req)
    end

    assert_response :no_content
    assert_equal 'waiting_application', @req.reload.status
  end

  # The case that sent somebody here: still `ready_to_apply`, and no
  # longer sendable.
  test 'a check older than a day is refused with a sentence, not a 404' do
    @validation.update_columns(finished_at: 2.days.ago)

    get submission_request_path(@req)

    assert_conform_schema 200
    assert_equal false, response.parsed_body['sendable']
    assert_includes response.parsed_body['send_blocked_reason'], 'more than 24 hours old'

    assert_no_enqueued_jobs only: ApplySubmissionRequestJob do
      with_exceptions_app { post submission_request_submission_path(@req) }
    end

    assert_conform_schema 422
    assert_includes response.parsed_body['error'], 'more than 24 hours old'
    assert_equal 'ready_to_apply', @req.reload.status
  end

  test 'a check that did not pass has nothing to send' do
    @validation.details.create!(severity: :error, code: 'TRD_R0001', message: 'no')

    get submission_request_path(@req)

    assert_conform_schema 200
    assert_equal false, response.parsed_body['sendable']

    with_exceptions_app { post submission_request_submission_path(@req) }

    assert_conform_schema 422
    assert_includes response.parsed_body['error'], 'did not pass'
  end

  test 'a request that has been put down says to reopen it' do
    @req.update_columns(closed_at: Time.current)

    with_exceptions_app { post submission_request_submission_path(@req) }

    assert_conform_schema 422
    assert_includes response.parsed_body['error'], 'Reopen'
  end

  # Ownership is still the only thing that hides a request. Everything
  # else is a refusal the caller can read.
  test "somebody else's request is still not found" do
    default_headers['Authorization'] = "Bearer #{users(:carol).api_key}"

    with_exceptions_app { post submission_request_submission_path(@req) }

    assert_conform_schema 404
  end

  # Running the check again is the way out of a stale one, and the only
  # refusal above that is not about the file. Without it the sentence
  # names something the submitter cannot do.
  test 'a stale check can be run again' do
    @validation.update_columns(finished_at: 2.days.ago)

    get submission_request_path(@req)

    assert_conform_schema 200
    assert_equal true, response.parsed_body['recheckable']

    assert_enqueued_with job: ValidateDDBJRecordJob do
      post submission_request_validation_path(@req)
    end

    assert_response :no_content
  end

  # A check replaces its predecessor. `has_one` and `create_validation!`
  # always meant that; now the database says so, which is what makes
  # "the validation" a single row rather than whichever one the planner
  # reached first.
  test 'a subject cannot collect a second check' do
    assert_raises ActiveRecord::RecordNotUnique do
      Validation.create!(subject: @req, progress: :finished, finished_at: Time.current)
    end
  end

  # The unique index caught this: `create_validation!` inserts rather than
  # replaces where the association was loaded before the first check
  # existed, so re-running left two rows and made "the validation"
  # whichever the planner reached. A re-check has to leave one.
  test 'running the check again replaces the previous one' do
    was = @validation.id

    perform_enqueued_jobs do
      post submission_request_validation_path(@req)
    end

    assert_equal 1, Validation.where(subject: @req).count
    assert_not_equal was, @req.reload.validation.id
  end

  test 'a request already in flight cannot be checked again' do
    @req.update_columns(status: SubmissionRequest.statuses[:applying])

    with_exceptions_app { post submission_request_validation_path(@req) }

    assert_conform_schema 422
    assert_includes response.parsed_body['error'], 'cannot be checked again'
  end

  # Nothing on the page is pressable for a reader who does not own it, so
  # there is no reason to explain a button they are not being offered.
  test 'a reader who does not own it is told neither' do
    set = SubmissionSet.create!(name: 'Deep sea study', owner: @alice)
    set.inclusions.create!(submission_request: @req, added_by: @alice)
    set.members.create!(user: users(:carol), invited_by: @alice, joined_at: Time.current)

    default_headers['Authorization'] = "Bearer #{users(:carol).api_key}"

    get submission_request_path(@req)

    assert_conform_schema 200
    assert_equal false, response.parsed_body['sendable']
    assert_nil response.parsed_body['send_blocked_reason']
    assert_equal false, response.parsed_body['recheckable']
  end
end
