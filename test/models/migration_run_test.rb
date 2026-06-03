require 'test_helper'

class MigrationRunTest < ActiveSupport::TestCase
  test 'uuid is auto-assigned before validation' do
    run = MigrationRun.create!(db: 'bioproject')

    assert_match(/\A[0-9a-f-]{36}\z/, run.uuid)
  end

  test 'default counters is an empty hash, default status is queued' do
    run = MigrationRun.create!(db: 'bioproject')

    assert_equal({}, run.counters)
    assert_equal 'queued', run.status
    assert run.queued_status?
  end

  test 'rejects unknown db' do
    run = MigrationRun.new(db: 'unknown')

    assert_not run.valid?
    assert_includes run.errors[:db], 'is not included in the list'
  end

  test 'counters_total sums every bucket' do
    run = MigrationRun.create!(db: 'biosample', counters: {'created' => 10, 'skipped' => 5, 'failed' => 2})

    assert_equal 17, run.counters_total
  end

  test 'progress_percent floors at 0 when total is nil/0 and caps at 100' do
    run = MigrationRun.create!(db: 'bioproject')
    assert_equal 0, run.progress_percent

    run.update!(total: 100, counters: {'created' => 50})
    assert_equal 50, run.progress_percent

    run.update!(total: 100, counters: {'created' => 200}) # over-shoot edge
    assert_equal 100, run.progress_percent
  end

  test 'merge_counters! adds increments onto existing counters atomically' do
    run = MigrationRun.create!(db: 'bioproject', counters: {'created' => 3})

    run.merge_counters!(created: 7, skipped: 2)

    assert_equal({'created' => 10, 'skipped' => 2}, run.counters)
  end

  test 'merge_counters! is a no-op for empty input (avoids spurious UPDATE)' do
    run = MigrationRun.create!(db: 'bioproject', counters: {'created' => 3})
    before = run.updated_at

    travel 1.second do
      run.merge_counters!({})
    end

    assert_equal before.to_i, run.reload.updated_at.to_i, 'empty increments must not bump updated_at'
  end

  test 'append_error! concatenates messages with newlines, skipping blanks' do
    run = MigrationRun.create!(db: 'bioproject')

    run.append_error!('first error')
    run.append_error!('second error')
    run.append_error!(nil) # tolerated

    assert_equal "first error\nsecond error", run.reload.error_log
  end
end
