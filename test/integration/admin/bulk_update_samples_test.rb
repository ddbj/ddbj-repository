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

    assert_redirected_to admin_submission_path(@submission)
    assert_match(/Bulk-updated 2 sample/, flash[:notice])

    assert_equal 'curating', @sample_a.reload.status
    assert_equal 'curating', @sample_b.reload.status
  end

  test 'PATCH bulk_update_samples sets assignee on every sample' do
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {assignee_id: users(:bob).id.to_s}}

    assert_redirected_to admin_submission_path(@submission)
    assert_equal users(:bob), @sample_a.reload.assignee
    assert_equal users(:bob), @sample_b.reload.assignee
  end

  test 'PATCH bulk_update_samples sets both status AND assignee in one go' do
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {status: 'public', assignee_id: users(:bob).id.to_s}}

    assert_redirected_to admin_submission_path(@submission)
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

    assert_redirected_to admin_submission_path(@submission)
    assert_nil @sample_a.reload.assignee
    assert_nil @sample_b.reload.assignee
  end

  test 'PATCH bulk_update_samples empty status keeps existing status (leave-as-is)' do
    original_a = @sample_a.status
    original_b = @sample_b.status

    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {status: '', assignee_id: users(:bob).id.to_s}}

    assert_redirected_to admin_submission_path(@submission)
    assert_equal original_a, @sample_a.reload.status, 'blank status field must be leave-as-is'
    assert_equal original_b, @sample_b.reload.status
    assert_equal users(:bob), @sample_a.assignee, 'assignee still applied'
  end

  test 'PATCH bulk_update_samples rejects unknown status (manual cast guard)' do
    original_a = @sample_a.status
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {status: 'nope_not_a_status'}}

    assert_redirected_to admin_submission_path(@submission)
    assert_match(/Unknown status/, flash[:alert])
    assert_equal original_a, @sample_a.reload.status
  end

  test 'PATCH bulk_update_samples rejects non-admin assignee (manual guard)' do
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {assignee_id: users(:alice).id.to_s}}

    assert_redirected_to admin_submission_path(@submission)
    assert_match(/must be an admin user/, flash[:alert])
    assert_nil @sample_a.reload.assignee
  end

  test 'PATCH bulk_update_samples with both fields blank refuses the no-op' do
    patch bulk_update_samples_admin_submission_path(@submission),
          params: {bulk_sample: {status: '', assignee_id: ''}}

    assert_redirected_to admin_submission_path(@submission)
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

  test 'show page renders the bulk-sample form for BS submissions with samples' do
    get admin_submission_path(@submission)

    assert_response :ok
    assert_match 'Bulk update all samples',                                response.body
    assert_match bulk_update_samples_admin_submission_path(@submission),   response.body
    assert_match 'name="bulk_sample[status]"',                             response.body
    assert_match 'name="bulk_sample[assignee_id]"',                        response.body
  end
end
