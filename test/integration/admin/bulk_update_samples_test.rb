require 'test_helper'

class AdminBulkUpdateSamplesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)

    @submission = submissions(:biosample)
    @sample_a   = samples(:first)
    @sample_b   = samples(:second)
  end

  test 'PATCH bulk_update_samples sets status on every sample in one SQL' do
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {status: 'curating'}}

    assert_redirected_to samples_admin_submission_request_path(@submission.request)
    assert_match(/Bulk-updated 2 sample/, flash[:notice])

    assert_equal 'curating', @sample_a.reload.status
    assert_equal 'curating', @sample_b.reload.status
  end

  test 'PATCH bulk_update_samples sets assignee on every sample' do
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {assignee_id: users(:bob).id.to_s}}

    assert_redirected_to samples_admin_submission_request_path(@submission.request)
    assert_equal users(:bob), @sample_a.reload.assignee
    assert_equal users(:bob), @sample_b.reload.assignee
  end

  test 'PATCH bulk_update_samples sets both status AND assignee in one go' do
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {status: 'public', assignee_id: users(:bob).id.to_s}}

    assert_redirected_to samples_admin_submission_request_path(@submission.request)
    assert_equal 'public',    @sample_a.reload.status
    assert_equal users(:bob), @sample_a.assignee
    assert_equal 'public',    @sample_b.reload.status
    assert_equal users(:bob), @sample_b.assignee
  end

  test 'PATCH bulk_update_samples assignee_id="0" explicitly unassigns' do
    @sample_a.update!(assignee: users(:bob))
    @sample_b.update!(assignee: users(:bob))

    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {assignee_id: '0'}}

    assert_redirected_to samples_admin_submission_request_path(@submission.request)
    assert_nil @sample_a.reload.assignee
    assert_nil @sample_b.reload.assignee
  end

  test 'PATCH bulk_update_samples empty status keeps existing status (leave-as-is)' do
    original_a = @sample_a.status
    original_b = @sample_b.status

    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {status: '', assignee_id: users(:bob).id.to_s}}

    assert_redirected_to samples_admin_submission_request_path(@submission.request)
    assert_equal original_a, @sample_a.reload.status, 'blank status field must be leave-as-is'
    assert_equal original_b, @sample_b.reload.status
    assert_equal users(:bob), @sample_a.assignee, 'assignee still applied'
  end

  test 'PATCH bulk_update_samples rejects unknown status (manual cast guard)' do
    original_a = @sample_a.status
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {status: 'nope_not_a_status'}}

    assert_redirected_to samples_admin_submission_request_path(@submission.request)
    assert_match(/Unknown status/, flash[:alert])
    assert_equal original_a, @sample_a.reload.status
  end

  test 'PATCH bulk_update_samples rejects non-admin assignee (manual guard)' do
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {assignee_id: users(:alice).id.to_s}}

    assert_redirected_to samples_admin_submission_request_path(@submission.request)
    assert_match(/must be an admin user/, flash[:alert])
    assert_nil @sample_a.reload.assignee
  end

  test 'PATCH bulk_update_samples with both fields blank refuses the no-op' do
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {status: '', assignee_id: ''}}

    assert_redirected_to samples_admin_submission_request_path(@submission.request)
    assert_match(/No changes specified/, flash[:alert])
  end

  test 'PATCH bulk_update_samples 404s for non-BS submissions' do
    patch bulk_update_samples_admin_submission_path(submissions(:bioproject)),
          params: {bulk_sample: {status: 'public'}}

    assert_response :not_found
  end

  test 'PATCH bulk_update_samples requires admin auth' do
    sign_in_as users(:carol)
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {status: 'public'}}

    assert_response :forbidden
  end

  # --- scoping -----------------------------------------------------------
  # The Samples screen offers two target sets and they must not be
  # confusable: the checkboxes on this page, or every row matching the
  # filter (which can be far more rows than the browser ever rendered).

  test 'scope=selected only touches the checkboxed samples' do
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {scope: 'selected', sample_ids: [@sample_a.id.to_s], status: 'curating'}}

    assert_match(/Bulk-updated 1 sample/, flash[:notice])
    assert_equal 'curating', @sample_a.reload.status
    assert_equal 'public',   @sample_b.reload.status
  end

  # The filtered set is re-derived server-side from the filter params, not
  # from a posted id list — otherwise "all 100K matching" could not work.
  # A sample bulk edit reaches no record field, so it leaves no patch —
  # the event is the only place the actor and the count survive.
  test 'a bulk edit records an event carrying the actor and the row count' do
    assert_difference 'CurationEvent.count', 1 do
      patch bulk_update_samples_admin_submission_path(@submission),
            params: {bulk_sample: {status: 'curating', assignee_id: users(:bob).id.to_s}}
    end

    event = CurationEvent.last

    assert_equal 'admin:bob', event.actor
    assert_equal 2,           event.row_count
    assert_equal 'set 2 samples to curating and assigned them to bob', event.summary
  end

  test 'the recorded count follows the chosen scope, not the whole submission' do
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {scope: 'selected', sample_ids: [@sample_a.id.to_s], status: 'curating'}}

    assert_equal 1, CurationEvent.last.row_count
  end

  test 'scope=selected with nothing ticked is refused rather than reported as a no-op success' do
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {scope: 'selected', status: 'curating'}}

    assert_match(/No samples selected/, flash[:alert])
    assert_equal 'private', @sample_a.reload.status
  end

  test 'scope=filtered re-derives the target set from the filter params' do
    patch bulk_update_samples_admin_submission_path(@submission, q: 'sample-2'),
          params: {bulk_sample: {scope: 'filtered', sample_ids: [@sample_a.id.to_s], status: 'curating'}}

    assert_match(/Bulk-updated 1 sample/, flash[:notice])
    assert_equal 'private',  @sample_a.reload.status, 'a posted id outside the filter must not be touched'
    assert_equal 'curating', @sample_b.reload.status
  end

  test 'the redirect keeps the filter so the curator lands back on the same view' do
    patch bulk_update_samples_admin_submission_path(@submission, q: 'sample-2'),
          params: {bulk_sample: {scope: 'filtered', status: 'curating'}}

    assert_redirected_to samples_admin_submission_request_path(@submission.request, q: 'sample-2')
  end

  test 'the samples tab renders the bulk bar' do
    get samples_admin_submission_request_path(@submission.request)

    assert_response :ok
    assert_match bulk_update_samples_admin_submission_path(@submission), response.body
    assert_match 'name="bulk_sample[status]"',                          response.body
    assert_match 'name="bulk_sample[assignee_id]"',                     response.body
    assert_match 'name="bulk_sample[scope]"',                           response.body
    assert_match 'name="bulk_sample[sample_ids][]"',                    response.body
  end
end
