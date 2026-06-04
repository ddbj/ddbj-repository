require 'test_helper'

class AdminSamplesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)

    @sample     = samples(:first)
    @submission = @sample.submission
  end

  test 'GET edit renders the form pre-populated with current values' do
    @sample.update!(status: 'curating', assignee: users(:bob))

    get edit_admin_sample_path(@sample)

    assert_response :ok
    assert_match 'Edit sample',                                    response.body
    assert_match @sample.sample_name,                              response.body
    assert_match 'name="sample[status]"',                          response.body
    assert_match 'name="sample[assignee_id]"',                     response.body
  end

  test 'PATCH update changes both status and assignee' do
    patch admin_sample_path(@sample),
          params: {sample: {status: 'public', assignee_id: users(:bob).id.to_s}}

    assert_redirected_to admin_submission_path(@submission)
    assert_match(/updated/, flash[:notice])
    @sample.reload
    assert_equal 'public',    @sample.status
    assert_equal users(:bob), @sample.assignee
  end

  test 'PATCH update with blank status keeps the existing status (leave-as-is)' do
    original = @sample.status

    patch admin_sample_path(@sample),
          params: {sample: {status: '', assignee_id: users(:bob).id.to_s}}

    assert_redirected_to admin_submission_path(@submission)
    assert_equal original,    @sample.reload.status, 'blank status field must be leave-as-is'
    assert_equal users(:bob), @sample.assignee
  end

  test 'PATCH update assignee_id="0" explicitly unassigns' do
    @sample.update!(assignee: users(:bob))

    patch admin_sample_path(@sample),
          params: {sample: {assignee_id: '0'}}

    assert_redirected_to admin_submission_path(@submission)
    assert_nil @sample.reload.assignee
  end

  test 'PATCH update with both fields blank refuses the no-op' do
    patch admin_sample_path(@sample),
          params: {sample: {status: '', assignee_id: ''}}

    assert_redirected_to edit_admin_sample_path(@sample)
    assert_match(/No changes specified/, flash[:alert])
  end

  test 'PATCH update rejects non-admin assignee (AdminAssignable validation)' do
    patch admin_sample_path(@sample),
          params: {sample: {assignee_id: users(:alice).id.to_s}}

    assert_redirected_to edit_admin_sample_path(@sample)
    assert_match(/admin user/i, flash[:alert])
  end

  test 'PATCH update rejects unknown status (Lifecycleable enum validate: true)' do
    patch admin_sample_path(@sample),
          params: {sample: {status: 'nope_not_a_status'}}

    assert_redirected_to edit_admin_sample_path(@sample)
  end

  test 'submission show samples table renders Edit link to per-sample edit' do
    get admin_submission_path(@submission)

    assert_response :ok
    assert_match edit_admin_sample_path(@sample), response.body
  end

  test 'PATCH update requires admin auth' do
    sign_in_as users(:carol)
    patch admin_sample_path(@sample),
          params: {sample: {status: 'public'}}

    assert_response :forbidden
  end
end
