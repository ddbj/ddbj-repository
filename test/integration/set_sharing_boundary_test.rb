require 'test_helper'

# What being able to READ somebody's submission through a set does not
# get you.
#
# `SubmissionRequestsController#show` was widened to `readable_by`; every
# other endpoint that takes a submission request id stayed owner-scoped.
# That boundary is the whole security story of the widening, and it is
# held by one line in each of five controllers — exactly the shape a
# future refactor "helpfully" unifies. These tests are what would notice.
class GroupSharingBoundaryTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)
    @carol = users(:carol)

    # Carol's submission, shared into a set Alice is in.
    @theirs = @carol.submission_requests.create!(db: 'bioproject', status: :ready_to_apply, migration_run_id: SecureRandom.uuid)
    attach_ddbj_record @theirs

    set = SubmissionSet.create!(name: 'Deep sea study', owner: @alice)
    set.members.create!(user: @carol, invited_by: @alice, joined_at: Time.current)
    set.inclusions.create!(submission_request: @theirs, added_by: @carol)

    default_headers['Authorization'] = "Bearer #{@alice.api_key}"
  end

  test 'reading it is allowed' do
    get submission_request_path(@theirs)

    assert_conform_schema 200
    assert_equal false, response.parsed_body['owned']
  end

  test 'the conversation is not' do
    with_exceptions_app { get submission_request_messages_path(@theirs) }
    assert_response :not_found

    with_exceptions_app do
      post submission_request_messages_path(@theirs),
           params:  {submission_message: {body: 'Hello'}}.to_json,
           headers: {'Content-Type' => 'application/json'}
    end
    assert_response :not_found
  end

  # The set's review link is any member's to mint and to revoke — but what
  # it carries is not. Handing somebody else's accession to an anonymous
  # link is the same escalation as putting their submission into a set of
  # your own, one floor up.
  test 'putting their accession on the set review link is not' do
    submission = Submission.create!(user: @carol, db: 'bioproject')
    submission.create_project!(project_type: :primary, title: 'Theirs', accession: 'PRJDB000099')
    @theirs.update_columns(submission_id: submission.id)

    set = SubmissionSet.sole

    post set_reviewer_access_path(set),
         params:  {reviewer_access: {expires_at: 1.week.from_now.iso8601}}.to_json,
         headers: {'Content-Type' => 'application/json'}

    assert_response :created

    with_exceptions_app do
      post set_reviewer_access_accessions_path(set),
           params:  {accessions: ['PRJDB000099']}.to_json,
           headers: {'Content-Type' => 'application/json'}
    end

    assert_conform_schema 403
    assert_includes response.parsed_body['error'], 'PRJDB000099'
  end

  test 'closing it is not' do
    with_exceptions_app { post submission_request_closure_path(@theirs) }
    assert_response :not_found
  end

  test 'polling its status is not' do
    with_exceptions_app { get submission_request_status_path(@theirs) }
    assert_response :not_found
  end

  test 'applying it is not' do
    with_exceptions_app { post submission_request_submission_path(@theirs) }
    assert_response :not_found
  end

  # The accessions are a large part of why somebody opens a colleague's
  # submission at all, so the nested list follows the detail screen.
  test 'the submission and its accessions follow the detail screen' do
    submission = Submission.create!(user: @carol, db: 'bioproject')
    attach_submission_files submission
    @theirs.update_columns(submission_id: submission.id)

    get submission_accessions_path(submission)
    assert_conform_schema 200

    get submission_path(submission)
    assert_conform_schema 200
  end

  # The record's content is a larger disclosure than the list: the list
  # gives a member an accession and a few labelled facts, this gives them
  # every field of that row's subtree. Same population, deliberately —
  # and pinned here, because this file is what would notice if the line
  # in the controller moved.
  test "a member reads a colleague's record content, and a stranger does not" do
    submission = Submission.create!(user: @carol, db: 'bioproject')
    attach_submission_files submission
    @theirs.update_columns(submission_id: submission.id)

    project = submission.create_project!(accession: 'PRJDB009001', status: 'public', project_type: 'primary')
    submission.append_update!({'project' => {'title' => 'Theirs'}}, actor: 'test')

    get submission_accession_path(submission, project.accession)

    assert_conform_schema 200
    assert_equal 'Theirs', response.parsed_body['sections'].sole.dig('node', 'value')

    default_headers['Authorization'] = "Bearer #{users(:dave).api_key}"

    with_exceptions_app { get submission_accession_path(submission, project.accession) }

    assert_conform_schema 404
  end

  # ...but the flat cross-submission walk stays one submitter's. It is a
  # synchronisation endpoint: a client keeps a local copy from it, and
  # somebody else's rows appearing in that copy is the one thing it must
  # not do.

  test 'the cross-submission accession walk stays mine' do
    submission = Submission.create!(user: @carol, db: 'st26')
    @theirs.update_columns(submission_id: submission.id)

    entry = submission.entries.create!(accession: 'LC999999', entry_id: 'E1', locus_date: Date.current)

    get accessions_path

    assert_conform_schema 200
    assert_not_includes response.parsed_body.pluck('accession'), entry.accession
  end

  test 'taking the submission out of the set takes the reading with it' do
    SubmissionSetInclusion.destroy_all

    with_exceptions_app { get submission_request_path(@theirs) }

    assert_conform_schema 404
  end

  test 'removing the member takes the reading with it' do
    SubmissionSet.sole.members.find_by!(user_id: @carol.id).remove!

    with_exceptions_app { get submission_request_path(@theirs) }

    assert_conform_schema 404
  end
end
