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
  # Who a colleague's action speaks for. Answering is the work, so it
  # settles the thread for everybody; reading is not, and putting it
  # aside speaks only for the curator who did it.
  test 'a colleague answering settles it for everyone' do
    req = submission_requests(:bioproject)
    req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'a question')

    assert_equal 1, req.unread_message_count_for(users(:bob))
    assert_equal 1, req.unread_message_count_for(users(:dave))

    req.messages.create!(user: users(:dave), author_role: 'curator', body: 'answered')

    assert_equal 0, req.unread_message_count_for(users(:bob)), 'the work is done, for everyone'
  end

  test 'a colleague putting it aside speaks only for themselves' do
    req = submission_requests(:bioproject)
    req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'a question')

    req.mark_read_by!(users(:dave))

    assert_equal 0, req.unread_message_count_for(users(:dave))
    assert_equal 1, req.unread_message_count_for(users(:bob)), 'reading is not answering'
  end

  # A NULL marker means "put nothing aside", not "read nothing" — so
  # taking on a request whose conversation was settled long ago does not
  # report its whole history as waiting.
  test 'a settled thread is not unread to a curator who has never touched it' do
    req = submission_requests(:bioproject)
    req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'asked')
    req.messages.create!(user: users(:dave),  author_role: 'curator',   body: 'answered')

    assert_nil   req.participations.find_by(user_id: users(:bob).id)
    assert_equal 0, req.unread_message_count_for(users(:bob))
  end

  # A question that lands while a reply is being typed has not been read
  # by sending that reply.
  test 'putting aside acknowledges only what was in front of them' do
    req  = submission_requests(:bioproject)
    seen = req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'seen')
    req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'arrived since')

    req.mark_read_by!(users(:bob), through: seen.id)

    assert_equal 1, req.unread_message_count_for(users(:bob))
  end

  # Acknowledging a thread is the opposite of asking to hear more about
  # it. Enrolling a curator who glanced at an unclaimed request would put
  # it in their queue from then on, with Stop following the only way out.
  test 'marking a thread read does not start following it' do
    req = submission_requests(:bioproject)
    req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'asked')

    req.mark_read_by!(users(:bob))

    assert_not req.following?(users(:bob))
    assert_not_includes SubmissionRequest.involving(users(:bob)), req
  end

  test 'marking read again does not unsubscribe somebody who was following' do
    req = submission_requests(:bioproject)
    req.subscribe!(users(:bob))
    req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'asked')

    req.mark_read_by!(users(:bob))

    assert req.following?(users(:bob))
  end

  # A stale tab, rendered when more was unread, would otherwise reset the
  # position to an older message and resurrect what was already dealt
  # with.
  test 'the marker never moves backwards' do
    req   = submission_requests(:bioproject)
    older = req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'first')
    req.messages.create!(user: users(:alice), author_role: 'submitter', body: 'second')

    req.mark_read_by!(users(:bob))

    assert_equal 0, req.unread_message_count_for(users(:bob))

    req.mark_read_by!(users(:bob), through: older.id)

    assert_equal 0, req.unread_message_count_for(users(:bob)), 'a stale press must not resurrect'
  end

  # Unclaimed asks one question — has anybody claimed this — because a
  # two-part answer is not one a screen can ask somebody to remember.
  # Following is not claiming: it says who is listening, and a pool that
  # depended on that left work visible to nobody when the listener put
  # it aside.
  test 'following a request does not take it out of the pool' do
    req = submission_requests(:bioproject)
    req.subscribe!(users(:bob))

    assert_includes SubmissionRequest.unclaimed, req

    req.assign!(users(:bob))

    assert_not_includes SubmissionRequest.unclaimed, req, 'claiming does'
  end

  test 'unclaimed excludes anything assigned, and nothing else' do
    assigned  = submission_requests(:bioproject)
    involved  = submission_requests(:biosample)
    untouched = submission_requests(:st26)

    assigned.assign!(users(:bob))
    involved.participate!(users(:bob))

    unclaimed = SubmissionRequest.unclaimed

    assert_includes     unclaimed, untouched
    assert_includes     unclaimed, involved, 'somebody worked on it, but nobody has taken it'
    assert_not_includes unclaimed, assigned
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

  test 'readable_by covers your own and whatever a set has shared with you' do
    alice = users(:alice)
    carol = users(:carol)

    mine   = submission_requests(:bioproject) # alice's
    theirs = carol.submission_requests.create!(db: 'bioproject', status: :applied, migration_run_id: SecureRandom.uuid)

    assert_not_includes SubmissionRequest.readable_by(alice), theirs

    set = SubmissionSet.create!(name: 'Deep sea study', owner: alice)
    set.members.create!(user: carol, invited_by: alice, joined_at: Time.current)
    set.inclusions.create!(submission_request: theirs, added_by: carol)

    assert_includes SubmissionRequest.readable_by(alice), theirs
    assert_includes SubmissionRequest.readable_by(alice), mine

    # Ownership is what it always was. Sharing does not widen it, which is
    # what keeps `user.submission_requests` safe to write through.
    assert_not_includes alice.submission_requests, theirs
  end

  test 'an invitation nobody has walked through shares nothing' do
    alice = users(:alice)
    carol = users(:carol)

    theirs = carol.submission_requests.create!(db: 'bioproject', status: :applied, migration_run_id: SecureRandom.uuid)

    set = SubmissionSet.create!(name: 'Deep sea study', owner: carol)
    set.members.create!(email: 'alice@example.com', invited_by: carol)
    set.inclusions.create!(submission_request: theirs, added_by: carol)

    assert_not_includes SubmissionRequest.readable_by(alice), theirs
  end
end
