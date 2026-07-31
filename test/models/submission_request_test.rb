require 'test_helper'

class SubmissionRequestTest < ActiveSupport::TestCase
  # --- needs_submitter_action --------------------------------------------

  test 'a validated file waiting to be applied is the submitter move' do
    request = submission_requests(:st26)
    request.update_columns(status: SubmissionRequest.statuses.fetch('ready_to_apply'))

    assert_includes SubmissionRequest.needs_submitter_action, request
  end

  test 'a file that failed validation is the submitter move' do
    request = submission_requests(:st26)
    request.update_columns(status: SubmissionRequest.statuses.fetch('validation_failed'))

    assert_includes SubmissionRequest.needs_submitter_action, request
  end

  test 'an unanswered curator question is the submitter move' do
    request = submission_requests(:bioproject)
    request.messages.create!(user: users(:bob), author_role: 'curator', body: 'a question')

    assert_includes SubmissionRequest.needs_submitter_action, request
  end

  test 'a read curator question, and the submitter own message, are not' do
    request = submission_requests(:bioproject)
    request.messages.create!(user: users(:bob), author_role: 'curator', body: 'answered', read_at: Time.current)
    request.messages.create!(user: users(:alice), author_role: 'submitter', body: 'my reply')

    assert_not_includes SubmissionRequest.needs_submitter_action, request
  end

  # DDBJ's to fix, not the submitter's — resubmitting the same file would
  # not help. See CurationQueue's :stuck bucket, which does pick it up.
  test 'a failed application is not the submitter move' do
    request = submission_requests(:st26)
    request.update_columns(status: SubmissionRequest.statuses.fetch('application_failed'))

    assert_not_includes SubmissionRequest.needs_submitter_action, request
  end

  # --- finished / unfinished ---------------------------------------------

  test 'a request is finished once every curation row has left the pipeline' do
    request = submission_requests(:biosample)

    assert_includes SubmissionRequest.unfinished, request

    request.submission.samples.update_all(status: Lifecycleable::STATUSES.fetch('public'))

    assert_includes     SubmissionRequest.finished,   request
    assert_not_includes SubmissionRequest.unfinished, request
  end

  test 'one unfinished row keeps the whole request unfinished' do
    request = submission_requests(:biosample)

    request.submission.samples.update_all(status: Lifecycleable::STATUSES.fetch('public'))
    samples(:first).update!(status: 'curating')

    assert_includes SubmissionRequest.unfinished, request
  end

  # Withdrawn / canceled / permanently suppressed records are done with
  # too — showing them among the live ones implies work is still pending.
  test 'a withdrawn record counts as finished' do
    request = submission_requests(:bioproject)
    request.submission.project.update!(status: 'withdrawn')

    assert_includes SubmissionRequest.finished, request
  end

  # ST.26 is not curated through this system, so there are no rows to
  # finish — applied is as far as it goes.
  test 'an applied ST.26 request is finished, an unapplied one is not' do
    request = submission_requests(:st26)

    assert_includes SubmissionRequest.unfinished, request

    request.update_columns(status: SubmissionRequest.statuses.fetch('applied'))

    assert_includes SubmissionRequest.finished, request
  end

  test 'a request with no submission is never finished' do
    request = SubmissionRequest.new(user: users(:alice), db: 'bioproject')
    attach_ddbj_record(request)
    request.save!

    assert_includes SubmissionRequest.unfinished, request
  end
end
