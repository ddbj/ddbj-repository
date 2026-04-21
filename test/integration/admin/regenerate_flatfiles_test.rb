require 'test_helper'

class AdminRegenerateFlatfilesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:alice).tap { it.update!(admin: true) }

    default_headers['Authorization'] = "Bearer #{@admin.api_key}"
  end

  test 'show returns idle state when no progress exists' do
    get admin_regenerate_flatfiles_path

    assert_response :ok

    body = response.parsed_body

    assert_equal false, body['loading']
    assert_nil          body['total']
    assert_nil          body['processed']
  end

  test 'show returns loading state while regeneration is in progress' do
    RegenerateFlatfilesProgress.create!(total: 10, processed: 3)

    get admin_regenerate_flatfiles_path

    assert_response :ok

    body = response.parsed_body

    assert_equal true, body['loading']
    assert_equal 10,   body['total']
    assert_equal 3,    body['processed']
  end

  test 'show returns not-loading state when regeneration has completed' do
    RegenerateFlatfilesProgress.create!(total: 5, processed: 5)

    get admin_regenerate_flatfiles_path

    assert_response :ok

    body = response.parsed_body

    assert_equal false, body['loading']
    assert_equal 5,     body['total']
    assert_equal 5,     body['processed']
  end

  test 'create enqueues jobs for submissions with ddbj_record' do
    submission = submissions(:one)

    submission.ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    assert_enqueued_with job: RegenerateSubmissionFlatfilesJob do
      post admin_regenerate_flatfiles_path, params: {date: '2026-07-01'}, as: :json
    end

    assert_response :accepted

    progress = RegenerateFlatfilesProgress.order(created_at: :desc).first

    assert_equal 1, progress.total

    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.find { it['job_class'] == 'RegenerateSubmissionFlatfilesJob' }

    assert_equal Date.new(2026, 7, 1).to_s, enqueued['arguments'][3]['value']
    assert_equal false,                     enqueued['arguments'].last['force']
  end

  test 'create forwards force flag to the job' do
    submission = submissions(:one)

    submission.ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )

    post admin_regenerate_flatfiles_path, params: {date: '2026-07-01', force: true}, as: :json

    assert_response :accepted

    enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs.find { it['job_class'] == 'RegenerateSubmissionFlatfilesJob' }

    assert_equal true, enqueued['arguments'].last['force']
  end

  test 'create returns 403 for non-admin users' do
    default_headers['Authorization'] = "Bearer #{users(:carol).api_key}"

    post admin_regenerate_flatfiles_path, params: {date: '2026-07-01'}, as: :json

    assert_response :forbidden
  end
end
