require 'test_helper'

class AdminProjectsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)

    @submission = submissions(:bioproject)
    @project    = projects(:primary)
  end

  test 'PATCH update changes status + assignee on the BP Project' do
    patch admin_submission_project_path(@submission),
          params: {project: {status: 'curating', assignee_id: users(:bob).id}}

    assert_redirected_to admin_submission_path(@submission)
    assert_equal 'curating', @project.reload.status
    assert_equal users(:bob), @project.assignee
  end

  test 'PATCH update with assignee_id blank clears the assignee' do
    @project.update!(assignee: users(:bob))

    patch admin_submission_project_path(@submission),
          params: {project: {status: 'private', assignee_id: ''}}

    assert_redirected_to admin_submission_path(@submission)
    assert_nil @project.reload.assignee
  end

  test 'PATCH update rejects non-admin assignee (AdminAssignable validation)' do
    patch admin_submission_project_path(@submission),
          params: {project: {status: 'curating', assignee_id: users(:alice).id}}

    assert_redirected_to admin_submission_path(@submission)
    assert_match(/must be an admin user/, flash[:alert])
    assert_equal 'private', @project.reload.status, 'failed update must not mutate status either'
  end

  test 'PATCH update rejects unknown status (Lifecycleable enum validate: true)' do
    patch admin_submission_project_path(@submission),
          params: {project: {status: 'no_such_status'}}

    assert_redirected_to admin_submission_path(@submission)
    assert_match(/Status/, flash[:alert]) # ActiveRecord validation error surfaces in alert
    assert_equal 'private', @project.reload.status, 'failed update must not mutate the row'
  end

  test 'PATCH update 404s for a non-BP submission that lacks a Project row' do
    no_project_sub = submissions(:st26)
    assert_nil no_project_sub.project

    patch admin_submission_project_path(no_project_sub),
          params: {project: {status: 'curating'}}

    assert_response :not_found
  end

  test 'PATCH update requires admin auth' do
    sign_in_as users(:carol) # non-admin
    patch admin_submission_project_path(@submission),
          params: {project: {status: 'curating'}}

    assert_response :forbidden
  end

  test 'show page renders the curator-edit form for BP submissions' do
    get admin_submission_path(@submission)

    assert_response :ok
    assert_match 'Curator edit',                                response.body
    assert_match admin_submission_project_path(@submission),    response.body
    assert_match 'name="project[status]"',                      response.body
    assert_match 'name="project[assignee_id]"',                 response.body
  end

  test 'show page does NOT render the curator-edit form for non-BP submissions' do
    get admin_submission_path(submissions(:st26))

    assert_response :ok
    assert_no_match 'Curator edit', response.body
  end
end
