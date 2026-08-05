require 'test_helper'

class MigrationRunTest < ActiveSupport::TestCase
  # The job counts the source rows before sweeping them, so a zero total
  # on a live run means it is still counting — not that there is nothing
  # to do. The screen used to say "Total not yet enumerated" for both.
  test 'a live run with no total yet is enumerating, a finished one is not' do
    assert_predicate     new_run(status: :running, total: nil), :enumerating?
    assert_not_predicate new_run(status: :completed, total: 0), :enumerating?
    assert_not_predicate new_run(status: :running, total: 10),  :enumerating?
  end

  test 'the estimate comes from the rate this run has managed' do
    run = new_run(status: :running, total: 100, counters: {'created' => 25}, started_at: 20.minutes.ago)
    run.update_columns(updated_at: Time.current)

    # 20 minutes for a quarter of it, so about an hour left.
    assert_in_delta 60.minutes, run.eta, 1.minute
  end

  test 'there is no estimate before anything has been counted, or once it is over' do
    assert_nil new_run(status: :running, total: 100, started_at: 5.minutes.ago).eta
    assert_nil new_run(status: :completed, total: 100, counters: {'created' => 100}).eta
  end

  # The keys are the job's vocabulary; the order is the reader's. Sorting
  # by count moved the interesting line every run.
  test 'outcomes read in a fixed order, and an unknown key still shows' do
    run = new_run(counters: {'failed' => 2, 'created' => 20, 'skipped' => 8, 'invented' => 1})

    assert_equal %w[created skipped failed invented], run.outcome_rows.map(&:first)
    assert_equal 'Imported as a new submission', run.outcome_rows.first[1]
    assert_equal 'Invented', run.outcome_rows.last[1]
  end

  # One line per row answers "which row" and never "what do I fix".
  test 'failures group by cause, ignoring the identifiers the messages quote' do
    run = new_run
    run.update!(error_log: [
      '[PSUB000318] KeyError: key not found: organism',
      '[PSUB000402] KeyError: key not found: organism',
      '[PSUB000455] ArgumentError: unknown prefix',
      'ABANDONED: superseded by a new run'
    ].join("\n"))

    groups = run.failure_groups

    assert_equal 2, groups.size
    assert_equal 2, groups.first[:count]
    assert_equal %w[PSUB000318 PSUB000402], groups.first[:source_ids]
    assert_match(/key not found: organism/, groups.first[:cause])

    # The run-level line is not a row failure, and is kept apart.
    assert_equal ['ABANDONED: superseded by a new run'], run.notices
    assert_equal 'superseded by a new run', run.abandoned_reason
  end

  # Two rows that failed the same way differ only in the ids their
  # messages quote — grouping on the raw text would give each its own
  # group of one, which is the log again with extra steps.
  test 'messages that differ only by an identifier are one cause' do
    run = new_run
    run.update!(error_log: [
      '[PSUB000318] RuntimeError: no submission for PSUB000318 (attempt 1)',
      '[PSUB000402] RuntimeError: no submission for PSUB000402 (attempt 2)'
    ].join("\n"))

    assert_equal 1, run.failure_groups.size
    assert_equal 2, run.failure_groups.first[:count]
  end

  # The rule is one run per database, so the screen leads with that
  # rather than with a list the reader has to reconstruct it from.
  test 'the state of a database is what is running now, or what ran last' do
    old     = new_run(db: 'bioproject', status: :completed, started_at: 2.days.ago)
    running = new_run(db: 'bioproject', status: :running,   started_at: 1.hour.ago)

    state = MigrationRun.state_of('bioproject')

    assert_equal running, state[:current]
    assert_equal old,     state[:last]

    idle = MigrationRun.state_of('biosample')

    assert_nil idle[:current]
    assert_nil idle[:last]
  end

  private

  def new_run(**attrs)
    MigrationRun.create!({db: 'bioproject', status: :running, started_at: Time.current}.merge(attrs))
  end
end
