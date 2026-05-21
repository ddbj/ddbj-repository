require 'test_helper'

class AdminRegenerateFlatfilesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)
  end

  test 'show returns idle state when no progress exists' do
    get admin_regenerate_flatfiles_path

    assert_response :ok
    assert_match 'Regenerate Flatfiles', response.body
    assert_no_match 'Processing:',       response.body
  end

  test 'show renders progress bar while regeneration is in progress' do
    RegenerateFlatfilesProgress.create!(total: 10, processed: 3)

    get admin_regenerate_flatfiles_path

    assert_response :ok
    assert_match 'Processing: 3 succeeded',         response.body
    assert_match 'data-controller="auto-refresh"',  response.body
  end

  test 'show counts failed jobs in progress so the run can finish despite failures' do
    RegenerateFlatfilesProgress.create!(total: 10, processed: 7, failed: 3)

    get admin_regenerate_flatfiles_path

    assert_response :ok
    assert_match 'Completed at',                       response.body
    assert_match '7 succeeded, 3 failed',              response.body
    assert_no_match 'data-controller="auto-refresh"',  response.body
  end

  test 'show renders completion alert with the finish timestamp' do
    progress = RegenerateFlatfilesProgress.create!(total: 5, processed: 5)

    get admin_regenerate_flatfiles_path

    assert_response :ok
    assert_match "Completed at #{progress.updated_at.to_fs(:db)}",  response.body
    assert_match '5 succeeded.',                                    response.body
    assert_no_match 'data-controller="auto-refresh"',               response.body
  end

  test 'create enqueues jobs for submissions with ddbj_record' do
    submission = submissions(:st26)

    submission.ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    assert_enqueued_with job: RegenerateSubmissionFlatfilesJob do
      post admin_regenerate_flatfiles_path, params: {date: '2026-07-01'}
    end

    assert_redirected_to admin_regenerate_flatfiles_path

    progress = RegenerateFlatfilesProgress.order(created_at: :desc).first

    assert_equal 1, progress.total

    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.find { it['job_class'] == 'RegenerateSubmissionFlatfilesJob' }

    assert_equal Date.new(2026, 7, 1).to_s, enqueued['arguments'][3]['value']
    assert_equal false,                     enqueued['arguments'].last['force']
  end

  test 'create forwards force flag to the job' do
    submission = submissions(:st26)

    submission.ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    post admin_regenerate_flatfiles_path, params: {date: '2026-07-01', force: '1'}

    assert_redirected_to admin_regenerate_flatfiles_path

    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.find { it['job_class'] == 'RegenerateSubmissionFlatfilesJob' }

    assert_equal true, enqueued['arguments'].last['force']
  end

  test 'create returns 403 for non-admin users' do
    sign_in_as users(:carol)

    with_exceptions_app do
      post admin_regenerate_flatfiles_path, params: {date: '2026-07-01'}
    end

    assert_response :forbidden
  end
end
