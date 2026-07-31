require 'test_helper'

# What pressing Regenerate actually starts: one job per submission that
# has a record, carrying the date and the force flag. The screen's three
# states are test/system/tools_test.rb.
#
# This is the most destructive action in the admin, and none of what it
# enqueues is visible from the page it redirects back to.
class AdminRegenerateFlatfilesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)

    submissions(:st26).ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )
  end

  test 'create enqueues a job per submission that has a record, and counts them' do
    assert_enqueued_with job: RegenerateSubmissionFlatfilesJob do
      post admin_regenerate_flatfiles_path, params: {date: '2026-07-01'}
    end

    assert_redirected_to admin_regenerate_flatfiles_path
    assert_equal 1, RegenerateFlatfilesProgress.order(created_at: :desc).first.total

    assert_equal Date.new(2026, 7, 1).to_s, enqueued_argument('value')
    assert_equal false,                     enqueued_argument('force')
  end

  test 'create forwards the force flag' do
    post admin_regenerate_flatfiles_path, params: {date: '2026-07-01', force: '1'}

    assert_redirected_to admin_regenerate_flatfiles_path
    assert_equal true, enqueued_argument('force')
  end

  test 'create returns 403 for non-admin users' do
    sign_in_as users(:carol)

    with_exceptions_app do
      post admin_regenerate_flatfiles_path, params: {date: '2026-07-01'}
    end

    assert_response :forbidden
  end

  private

  def enqueued_argument(key)
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { it['job_class'] == 'RegenerateSubmissionFlatfilesJob' }

    job['arguments'].find { it.is_a?(Hash) && it.key?(key) }&.fetch(key)
  end
end
