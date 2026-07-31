require 'test_helper'

class SubmissionRequestTest < ActiveSupport::TestCase
  # --- assignment ---------------------------------------------------------

  test 'assign! refuses a non-admin' do
    request = submission_requests(:st26)

    assert_raises(ArgumentError) { request.assign!(users(:alice)) }
    assert_nil request.reload.assignee
  end

  test 'assign! takes and releases an admin' do
    request = submission_requests(:st26)

    request.assign!(users(:bob))
    assert_equal users(:bob), request.reload.assignee

    request.assign!(nil)
    assert_nil request.reload.assignee
  end

  # A migration-sourced request carries no upload, and one that predates
  # Apply is exactly what the Unclaimed queue is for — the submitter-facing
  # attachment rule must not make either of them unclaimable.
  test 'assign! works on a request that could not pass its own validations' do
    request = submission_requests(:bioproject)
    request.ddbj_record.purge

    assert_not request.valid?

    request.assign!(users(:bob))

    assert_equal users(:bob), request.reload.assignee
  end

  # --- participation ------------------------------------------------------

  test 'participate! is idempotent' do
    request = submission_requests(:st26)

    3.times { request.participate!(users(:bob)) }

    assert_equal [users(:bob)], request.reload.participants
  end

  # Participation is written from the success path of actions that must
  # not fail because of it, and the submitter acting on their own request
  # is not a curator working on it.
  test 'participate! ignores a non-admin and a nil' do
    request = submission_requests(:st26)

    request.participate!(users(:alice))
    request.participate!(nil)

    assert_empty request.reload.participants
  end

  test 'involving finds requests a curator has worked on but does not own' do
    request = submission_requests(:st26)
    request.participate!(users(:bob))

    assert_includes     SubmissionRequest.involving(users(:bob)),   request
    assert_not_includes SubmissionRequest.assigned_to(users(:bob)), request
  end

  # Nobody owns it and nobody has been near it — the one section every
  # curator sees identically.
  test 'unclaimed excludes anything assigned or participated in' do
    assigned    = submission_requests(:bioproject)
    involved    = submission_requests(:biosample)
    untouched   = submission_requests(:st26)

    assigned.assign!(users(:bob))
    involved.participate!(users(:bob))

    unclaimed = SubmissionRequest.unclaimed

    assert_includes     unclaimed, untouched
    assert_not_includes unclaimed, assigned
    assert_not_includes unclaimed, involved
  end

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
