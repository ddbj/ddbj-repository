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

  # The panel polls its own run every three seconds for the length of the
  # run, and the history lists ten at a time. Splitting the paste to count
  # its lines meant a megabyte read and 127,604 strings allocated on every
  # one of those renders.
  test 'the accession count is stored, not counted from the list on the way out' do
    # Comma-separated and newline-separated, with a blank line and a
    # repeat — so the count is what a retry of this row would run, not
    # the lines it happens to be stored on.
    run = new_run(target: 'accessions', numbers: "X00001, X00002, X00003\n\nX00001", total: 1)

    assert_equal 3, run.accession_count
    assert_equal 3, run.numbers.lines.size
    assert_equal '3 accessions', run.scope_label

    # From the column, so the label survives a load that leaves the list
    # behind.
    assert_equal '3 accessions', RegenerateFlatfilesRun.without_numbers.find(run.id).scope_label
  end

  # What the screens report and what a retry re-runs come off the same
  # parse, so they cannot disagree about how many were named.
  test 'the count is the list a retry of the run would resolve' do
    run = new_run(target: 'accessions', numbers: "X00001, X00002\n\nX00001", total: 1)

    assert_equal RegenerationScope.retrying(run).numbers.size, run.accession_count
  end

  test 'the stored count follows the list when it changes' do
    run = new_run(target: 'accessions', numbers: 'X00001', total: 1)

    run.update! numbers: "X00001\nX00002"

    assert_equal 2, run.reload.accession_count
  end

  # The count is the list's, not the caller's. Guarding on "did the list
  # change" would leave a count assigned on its own standing, and then
  # the label the screens read is whatever somebody typed.
  test 'a count assigned on its own is replaced by the list it claims to describe' do
    run = new_run(target: 'accessions', numbers: "X00001\nX00002", accession_count: 99, total: 1)

    assert_equal 2, run.accession_count

    run.update! accession_count: 99

    assert_equal 2, run.reload.accession_count
  end

  # The callback and `without_numbers` only work together because the
  # callback checks first: the panel controller loads runs without the
  # column, and reading it on one of those raises.
  test 'a run loaded without its list can still be saved' do
    run  = new_run(target: 'accessions', numbers: 'X00001', total: 1)
    lean = RegenerateFlatfilesRun.without_numbers.find(run.id)

    lean.update! total: 2

    assert_equal 1, run.reload.accession_count
    assert_equal 2, run.total
  end

  # Six figures is the ordinary size of one of these runs.
  test 'the label delimits the count' do
    assert_equal '127,604 accessions', RegenerateFlatfilesRun.new(target: 'accessions', accession_count: 127_604).scope_label
  end

  test 'a run that named no accessions counts none' do
    run = new_run(target: 'all', total: 1)

    assert_equal 0, run.accession_count
    assert_equal 'All submissions', run.scope_label
  end

  # The one place the parse rule is written twice: rows that predate the
  # column are counted in SQL, and the suite loads the schema rather than
  # running migrations, so nothing else would exercise it.
  test 'the backfill counts what the callback counts' do
    require Rails.root.join('db/migrate/20260827000001_add_accession_count_to_regenerate_flatfiles_runs')

    texts = [
      nil,
      '',
      "   \n ",
      'X00001',
      "X00001\nX00002",
      'X00001, X00002,,X00003',
      "\nX00001\r\n\tX00002 \n",
      "X00001\nX00001",
      # Ruby's \s is ASCII-only and Postgres' is not: a full-width space
      # is one token to the parse and would be two to a `\s` pattern.
      "X00001\u3000X00002"
    ]

    runs = texts.map { new_run(target: 'accessions', numbers: it, total: 1) }

    RegenerateFlatfilesRun.update_all accession_count: -1
    ActiveRecord::Base.connection.execute AddAccessionCountToRegenerateFlatfilesRuns::BACKFILL

    runs.each do |run|
      expected = RegenerateFlatfilesRun.parse_numbers(run.numbers).size

      assert_equal expected, run.reload.accession_count, run.numbers.inspect
    end
  end

  private

  def new_run(**attrs)
    RegenerateFlatfilesRun.create!(
      {actor: 'admin:alice', target: 'all', started_at: Time.current}.merge(attrs)
    )
  end
end
