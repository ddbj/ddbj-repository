require 'test_helper'

class RegenerateFlatfilesRunTest < ActiveSupport::TestCase
  # Re-running a failed job from the queue browser — which the result
  # panel points developers at — lands a second outcome for a submission
  # this run has already counted as failed. Left alone, the run reports
  # more outcomes than it has submissions and goes on naming a failure
  # that has since succeeded.
  test 'counting a submission takes back the failure it is replacing' do
    run = new_run(total: 1)

    run.record_failure!(submissions(:st26), RuntimeError.new('boom'))

    assert_equal 1, run.reload.failed

    run.count! :regenerated, submissions(:st26)

    run.reload

    assert_equal 0,     run.failed
    assert_equal 1,     run.regenerated
    assert_equal 1,     run.done
    assert_empty        run.failures
    assert_equal :clean, run.outcome
  end

  # A submission destroyed while its job was in flight: storing the
  # reference would fail on the foreign key, inside the handler, and
  # replace the error being reported with one about the reporting.
  test 'a failure for a submission that has since gone is still recorded' do
    run        = new_run(total: 1)
    submission = submissions(:st26)

    submission.destroy!

    run.record_failure!(submission, RuntimeError.new('boom'))

    failure = run.failures.sole

    assert_nil   failure.submission_id
    assert_equal "submission ##{submission.id}", failure.label
    assert_equal 1, run.reload.failed
  end

  # Weighted by what each run got through. Most runs are two or three
  # accessions whose elapsed time is mostly queue latency; one vote each
  # would let those decide the estimate printed beside the
  # every-submission option.
  test 'the measured rate is weighted by the work each run did' do
    new_run(total: 1,   regenerated: 1,   started_at: 3.hours.ago, finished_at: 3.hours.ago + 30)
    new_run(total: 100, regenerated: 100, started_at: 2.hours.ago, finished_at: 2.hours.ago + 100)

    # 130 seconds over 101 submissions, not the mean of 30s and 1s.
    assert_in_delta 130.0 / 101, RegenerateFlatfilesRun.measured_rate, 0.01
  end

  test 'there is no rate until a run has finished' do
    new_run(total: 10, regenerated: 4, started_at: 1.hour.ago)

    assert_nil RegenerateFlatfilesRun.measured_rate
  end

  # `started_at` is when the jobs were enqueued, not when one first ran.
  # With a single completion the rate is however long the queue happened
  # to be — and the panel refreshes every three seconds, which is often
  # enough for somebody to read "about 2 years left".
  test 'no estimate until enough has finished for the queue wait to wash out' do
    run = new_run(total: 1000, regenerated: 1, started_at: 3.hours.ago)
    run.update_columns(updated_at: Time.current)

    assert_nil run.eta

    run.update!(regenerated: RegenerateFlatfilesRun::MIN_SAMPLE)

    assert_not_nil run.eta
  end

  # And a run whose workers went away freezes its estimate rather than
  # inflating it: elapsed is measured to the last progress, not to now.
  test 'the estimate stops growing once progress stops' do
    run = new_run(total: 100, regenerated: 50, started_at: 2.hours.ago)
    run.update_columns(updated_at: 1.hour.ago)

    assert_in_delta 1.hour, run.eta, 1.minute
  end

  # The escape hatch: a run whose worker died would otherwise block every
  # later press for good.
  test 'a run that has stopped reporting is no longer in flight' do
    fresh = new_run(total: 10, started_at: 1.minute.ago)
    dead  = new_run(total: 10, started_at: 5.hours.ago)

    dead.update_columns(updated_at: 5.hours.ago)

    assert_includes     RegenerateFlatfilesRun.in_flight, fresh
    assert_not_includes RegenerateFlatfilesRun.in_flight, dead

    # Still loading, though: whether its jobs are lost or merely queued
    # is not something the row knows, and declaring it over would invite
    # a second run over the same submissions.
    assert_predicate dead, :loading?
    assert_predicate dead, :stale?
  end

  private

  def new_run(**attrs)
    RegenerateFlatfilesRun.create!(
      {actor: 'admin:alice', target: 'all', started_at: Time.current}.merge(attrs)
    )
  end
end
