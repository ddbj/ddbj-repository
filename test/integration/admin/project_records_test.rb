require 'test_helper'

class AdminProjectRecordsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)

    @submission = submissions(:bioproject)
    @project    = projects(:primary)

    @submission.append_update!(
      {
        'schema_version' => 'v3',
        'project' => {'title' => 'Original title', 'description' => 'Original description.'}
      },
      actor:  'test-seed',
      source: :manual
    )
  end

  test 'PATCH update edits title + description in the patch chain' do
    chain_before = @submission.updates.count

    patch admin_submission_project_record_path(@submission),
          params: {project_record: {title: 'New title', description: 'New description.'}}

    assert_redirected_to admin_submission_path(@submission)
    @submission.reload
    assert_equal chain_before + 1, @submission.updates.count
    assert_equal 'New title',       @submission.materialised_record.dig('project', 'title')
    assert_equal 'New description.', @submission.materialised_record.dig('project', 'description')
  end

  test 'PATCH update mirrors title to the Project.title typed column' do
    patch admin_submission_project_record_path(@submission),
          params: {project_record: {title: 'Mirror title', description: 'Original description.'}}

    assert_equal 'Mirror title', @project.reload.title
  end

  test 'PATCH update with blank title drops the key AND nils the typed column' do
    patch admin_submission_project_record_path(@submission),
          params: {project_record: {title: '', description: 'Original description.'}}

    @submission.reload
    refute @submission.materialised_record.dig('project')&.key?('title'),
           'blank input must drop the title key (not store an empty string)'
    assert_nil @project.reload.title, 'typed column must also clear'
  end

  test 'PATCH update with blank description drops the description key' do
    patch admin_submission_project_record_path(@submission),
          params: {project_record: {title: 'Original title', description: ''}}

    refute @submission.reload.materialised_record.dig('project')&.key?('description')
  end

  test 'PATCH update with the same values is a no-op' do
    chain_before = @submission.updates.count

    patch admin_submission_project_record_path(@submission),
          params: {project_record: {title: 'Original title', description: 'Original description.'}}

    assert_match(/unchanged/, flash[:notice])
    assert_equal chain_before, @submission.reload.updates.count
  end

  test 'PATCH update 404s for non-BP submissions (no Project row)' do
    patch admin_submission_project_record_path(submissions(:st26)),
          params: {project_record: {title: 'X'}}

    assert_response :not_found
  end

  test 'show page renders the project-record form for BP submissions' do
    get admin_submission_path(@submission)

    assert_response :ok
    assert_match 'Project details',                                       response.body
    assert_match admin_submission_project_record_path(@submission),       response.body
    assert_match 'name="project_record[title]"',                          response.body
    assert_match 'name="project_record[description]"',                    response.body
  end

  test 'show page does NOT render the project-record form for non-BP submissions' do
    get admin_submission_path(submissions(:st26))

    assert_response :ok
    assert_no_match 'Project details', response.body
  end

  test 'PATCH update requires admin auth' do
    sign_in_as users(:carol)
    patch admin_submission_project_record_path(@submission),
          params: {project_record: {title: 'X'}}

    assert_response :forbidden
  end
end
