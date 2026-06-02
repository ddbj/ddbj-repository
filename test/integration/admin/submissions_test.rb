require 'test_helper'

class AdminSubmissionsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)
  end

  test 'index returns submissions across all DBs by default' do
    get admin_submissions_path

    assert_response :ok
    assert_match "Submission-#{submissions(:st26).id}",       response.body
    assert_match "Submission-#{submissions(:bioproject).id}", response.body
    assert_match "Submission-#{submissions(:biosample).id}",  response.body
  end

  test 'index filters by db' do
    get admin_submissions_path, params: {db: 'st26'}

    assert_response :ok
    assert_match    "Submission-#{submissions(:st26).id}",       response.body
    assert_no_match "Submission-#{submissions(:bioproject).id}", response.body
  end

  test 'index filters by user uid' do
    carol_request = SubmissionRequest.new(user: users(:carol), db: 'st26')
    attach_ddbj_record(carol_request)
    carol_request.save!

    carol_submission = Submission.new(db: 'st26', user: users(:carol), request: carol_request)
    attach_submission_files(carol_submission)
    carol_submission.save!

    get admin_submissions_path, params: {user: 'carol'}

    assert_response :ok
    assert_match    "Submission-#{carol_submission.id}",     response.body
    assert_no_match "Submission-#{submissions(:st26).id}",   response.body
  end

  test 'index returns 403 for non-admin users' do
    sign_in_as users(:carol)

    with_exceptions_app do
      get admin_submissions_path
    end

    assert_response :forbidden
  end

  test 'show renders the materialised v3 record' do
    submission = submissions(:bioproject)
    record     = {'project' => {'accession' => 'PRJDB502', 'title' => 'hello'}}
    submission.updates.create!(
      db:                       'bioproject',
      status:                   :applied,
      actor:                    'migration:test',
      source:                   :migration,
      patch:                    Oj.dump([{'op' => 'add', 'path' => '', 'value' => record}], mode: :strict),
      patch_canonical_version:  1
    )

    get admin_submission_path(submission)

    assert_response :ok
    assert_match "Submission-#{submission.id}", response.body
    assert_match 'PRJDB502',                    response.body
    assert_match 'hello',                       response.body
  end

  test 'show falls back gracefully when no updates have been applied' do
    submission = submissions(:bioproject)

    get admin_submission_path(submission)

    assert_response :ok
    assert_match 'nothing to materialise', response.body
  end

  test 'show ?as_of=N renders the snapshot at that update' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'v1'}}, actor: 'test')
    v2 = submission.append_update!({'project' => {'title' => 'v2'}}, actor: 'test')
    submission.append_update!({'project' => {'title' => 'v3'}}, actor: 'test')

    get admin_submission_path(submission, as_of: v2.id)

    assert_response :ok
    assert_match    'Viewing snapshot at',  response.body
    assert_match    'v2',                   response.body
    assert_no_match(/"title":\s*"v3"/,      response.body)
  end

  test 'show ?as_of=999999 warns and shows latest' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'only'}}, actor: 'test')

    get admin_submission_path(submission, as_of: 999_999)

    assert_response :ok
    assert_match 'not found on this submission', response.body
    assert_match 'only',                         response.body
  end
end
