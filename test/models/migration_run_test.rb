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
    before = run.reload.updated_at

    travel 1.second do
      run.merge_counters!({})
    end

    assert_equal before, run.reload.updated_at, 'empty increments must not bump updated_at'
  end

  test 'append_error! concatenates messages with newlines, skipping blanks' do
    run = MigrationRun.create!(db: 'bioproject')

    run.append_error!('first error')
    run.append_error!('second error')
    run.append_error!(nil) # tolerated

    assert_equal "first error\nsecond error", run.reload.error_log
  end

  # --- what the screens read ------------------------------------------

  # The job counts the source rows before sweeping them, so a zero total
  # on a live run means it is still counting — not that there is nothing
  # to do. The screen used to say "Total not yet enumerated" for both.
  test 'a live run with no total yet is enumerating, a finished one is not' do
    assert_predicate     new_run(status: :running, total: nil), :enumerating?
    assert_not_predicate new_run(status: :queued,  total: nil), :enumerating?
    assert_not_predicate new_run(status: :completed, total: 0), :enumerating?
    assert_not_predicate new_run(status: :running, total: 10),  :enumerating?
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

    groups = run.unimported_groups

    assert_equal 2, groups.size
    assert_equal 2, groups.first[:count]
    assert_equal %w[PSUB000318 PSUB000402], groups.first[:source_ids]
    assert_match(/key not found: organism/, groups.first[:cause])

    # The run-level line is not a row failure, and is kept apart.
    assert_equal ['ABANDONED: superseded by a new run'], run.notices
    assert_equal 'superseded by a new run', run.abandoned_reason
  end

  # `error.message` goes into the log verbatim, and a Postgres message
  # keeps its DETAIL on the next line. Splitting on newlines put those
  # continuations in with the run-level notices — a sweep with fifteen
  # thousand failures would have rendered fifteen thousand warnings.
  test 'a message that spans lines is one entry, not a row and a notice' do
    run = new_run
    run.update!(error_log: [
      '[PSUB000318] ActiveRecord::RecordNotUnique: PG::UniqueViolation: ERROR: duplicate key',
      'DETAIL:  Key (source_id)=(PSUB000318) already exists.',
      'ABANDONED: superseded by a new run'
    ].join("\n"))

    assert_equal 1, run.unimported_groups.size
    assert_equal 1, run.unimported_groups.first[:count]
    assert_equal ['ABANDONED: superseded by a new run'], run.notices

    # And the half worth reading is in the download.
    assert_match(/DETAIL:  Key/, run.unimported_text)
  end

  # A row refused for belonging to another submitter is counted
  # `cross_user`, and one that stopped the sweep is not counted at all.
  # Calling the section "failures" made it contradict the counter above.
  test 'rows that did not import include the ones not counted as failed' do
    run = new_run(counters: {'created' => 5, 'cross_user' => 1})
    run.update!(error_log: [
      '[PSUB000318] CROSS-USER: belongs to someone else',
      '[PSUB000402] STOPPED — StorageFailure: object storage is unreachable'
    ].join("\n"))

    assert_equal 2, run.unimported_groups.sum { it[:count] }
    assert_empty run.notices
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

    assert_equal 1, run.unimported_groups.size
    assert_equal 2, run.unimported_groups.first[:count]
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
