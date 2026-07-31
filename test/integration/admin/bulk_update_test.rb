require 'test_helper'

class AdminBulkUpdateTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)
  end

  # --- filter ---

  test 'index filter by status matches BP via project AND BS via samples' do
    projects(:primary).update!(status: 'curating')
    samples(:first).update!(status: 'curating')

    get admin_submission_requests_path, params: {status: 'curating'}

    assert_response :ok
    assert_match    admin_submission_request_path(submissions(:bioproject).request), response.body
    assert_match    admin_submission_request_path(submissions(:biosample).request),  response.body
    assert_no_match admin_submission_request_path(submissions(:st26).request),       response.body
  end

  test 'index filter by status hides submissions where no project/sample matches' do
    projects(:primary).update!(status: 'public')
    samples(:first).update!(status: 'public')
    samples(:second).update!(status: 'public')

    get admin_submission_requests_path, params: {status: 'curating'}

    assert_no_match admin_submission_request_path(submissions(:bioproject).request), response.body
    assert_no_match admin_submission_request_path(submissions(:biosample).request),  response.body
  end

  test 'index filter by assignee=<id> matches submissions where any project/sample is assigned' do
    projects(:primary).update!(assignee: users(:bob))

    get admin_submission_requests_path, params: {assignee: users(:bob).id.to_s}

    assert_match    admin_submission_request_path(submissions(:bioproject).request), response.body
    assert_no_match admin_submission_request_path(submissions(:biosample).request),  response.body
  end

  test 'index filter by assignee=0 matches submissions with at least one unassigned project/sample' do
    projects(:primary).update!(assignee: users(:bob))
    # BS samples remain unassigned (default).

    get admin_submission_requests_path, params: {assignee: '0'}

    assert_match    admin_submission_request_path(submissions(:biosample).request),  response.body
    assert_no_match admin_submission_request_path(submissions(:bioproject).request), response.body
  end

  test 'index filter ignores unknown status name (no error, no narrowing)' do
    get admin_submission_requests_path, params: {status: 'no_such_status'}

    assert_response :ok
    # All fixture submissions should still appear.
    assert_match admin_submission_request_path(submissions(:bioproject).request), response.body
    assert_match admin_submission_request_path(submissions(:biosample).request),  response.body
    assert_match admin_submission_request_path(submissions(:st26).request),       response.body
  end

  # --- index UI ---

  test 'index renders a per-row checkbox and the bulk bar' do
    get admin_submission_requests_path

    assert_response :ok
    assert_match 'selected on this page',                            response.body
    assert_match bulk_update_admin_submissions_path,                 response.body
    assert_match 'name="bulk[submission_ids][]"',                    response.body
    assert_match 'name="bulk[status]"',                              response.body
    assert_match 'name="bulk[assignee_id]"',                         response.body
  end

  # --- bulk_update ---

  test 'bulk_update applies status to BP project AND every BS sample of selected submissions' do
    post bulk_update_admin_submissions_path,
          params: {bulk: {
            submission_ids: [submissions(:bioproject).id.to_s, submissions(:biosample).id.to_s],
            status:         'public'
          }}

    assert_redirected_to admin_submission_requests_path
    assert_equal 'public', projects(:primary).reload.status
    assert_equal 'public', samples(:first).reload.status
    assert_equal 'public', samples(:second).reload.status
  end

  # One event per submission, not one for the batch: the activity feed is
  # read per request, so "N rows" has to be that submission's count.
  test 'bulk_update records one event per submission with its own row count' do
    assert_difference 'CurationEvent.count', 2 do
      post bulk_update_admin_submissions_path,
            params: {bulk: {
              submission_ids: [submissions(:bioproject).id.to_s, submissions(:biosample).id.to_s],
              status:         'public'
            }}
    end

    by_submission = CurationEvent.all.index_by(&:submission_id)

    assert_equal 1, by_submission.fetch(submissions(:bioproject).id).row_count
    assert_equal 2, by_submission.fetch(submissions(:biosample).id).row_count
    assert_equal 'set 2 samples to public', by_submission.fetch(submissions(:biosample).id).summary
  end

  test 'bulk_update applies assignee across BP project AND BS samples' do
    post bulk_update_admin_submissions_path,
          params: {bulk: {
            submission_ids: [submissions(:bioproject).id.to_s, submissions(:biosample).id.to_s],
            assignee_id:    users(:bob).id.to_s
          }}

    assert_redirected_to admin_submission_requests_path
    assert_equal users(:bob), projects(:primary).reload.assignee
    assert_equal users(:bob), samples(:first).reload.assignee
    assert_equal users(:bob), samples(:second).reload.assignee
  end

  test 'bulk_update assignee_id="0" sets nil across selected rows' do
    projects(:primary).update!(assignee: users(:bob))
    samples(:first).update!(assignee:    users(:bob))

    post bulk_update_admin_submissions_path,
          params: {bulk: {
            submission_ids: [submissions(:bioproject).id.to_s, submissions(:biosample).id.to_s],
            assignee_id:    '0'
          }}

    assert_redirected_to admin_submission_requests_path
    assert_nil projects(:primary).reload.assignee
    assert_nil samples(:first).reload.assignee
  end

  test 'bulk_update with no submissions selected refuses' do
    post bulk_update_admin_submissions_path, params: {bulk: {status: 'public'}}

    assert_redirected_to admin_submission_requests_path
    assert_match(/No submissions selected/, flash[:alert])
  end

  test 'bulk_update with both fields blank refuses' do
    post bulk_update_admin_submissions_path,
          params: {bulk: {
            submission_ids: [submissions(:bioproject).id.to_s],
            status:         '',
            assignee_id:    ''
          }}

    assert_redirected_to admin_submission_requests_path
    assert_match(/No changes specified/, flash[:alert])
  end

  test 'bulk_update rejects unknown status' do
    post bulk_update_admin_submissions_path,
          params: {bulk: {
            submission_ids: [submissions(:bioproject).id.to_s],
            status:         'nope_not_a_status'
          }}

    assert_redirected_to admin_submission_requests_path
    assert_match(/Unknown status/, flash[:alert])
  end

  test 'bulk_update rejects non-admin assignee' do
    post bulk_update_admin_submissions_path,
          params: {bulk: {
            submission_ids: [submissions(:bioproject).id.to_s],
            assignee_id:    users(:alice).id.to_s
          }}

    assert_redirected_to admin_submission_requests_path
    assert_match(/must be an admin user/, flash[:alert])
  end

  test 'bulk_update preserves filter params in the redirect' do
    post bulk_update_admin_submissions_path,
          params: {db: 'bioproject', status: 'public',
                   bulk: {submission_ids: [submissions(:bioproject).id.to_s], status: 'curating'}}

    assert_redirected_to admin_submission_requests_path(db: 'bioproject', status: 'public')
  end

  test 'bulk_update requires admin auth' do
    sign_in_as users(:carol)
    post bulk_update_admin_submissions_path,
          params: {bulk: {submission_ids: [submissions(:bioproject).id.to_s], status: 'public'}}

    assert_response :forbidden
  end
end
