require 'test_helper'

# What pressing Regenerate actually starts: one job per submission that
# can produce a flatfile, carrying the date and the accessions it goes
# to, and a run row recording who asked for it and what they asked for.
# The screen itself is test/system/tools_test.rb.
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

  test 'create enqueues a job per submission in scope, and records the run' do
    assert_enqueued_with job: RegenerateSubmissionFlatfilesJob do
      post admin_regenerate_flatfiles_path, params: {target: 'all', confirm: 'all', date_mode: 'set', date: '2026-07-01'}
    end

    assert_redirected_to admin_regenerate_flatfiles_path

    run = RegenerateFlatfilesRun.sole

    assert_equal 1,                     run.total
    assert_equal 'all',                 run.target
    assert_equal "admin:#{users(:bob).uid}", run.actor
    assert_equal Date.new(2026, 7, 1),  run.locus_date

    assert_equal Date.new(2026, 7, 1).to_s, enqueued_argument('value')

    # Every submission is covered, so every entry takes the date and
    # there is no list to carry.
    assert_nil enqueued_argument('accessions')
    assert_nil RegenerateFlatfilesRun.sole.numbers
    assert_equal 0, RegenerateFlatfilesRun.sole.accession_count
  end

  # The list is the job's, not just the scope's: it decides whose LOCUS
  # date moves, and the entries beside them in the same submission keep
  # theirs.
  test 'create forwards the accessions each job is to date' do
    accession = named_accession

    post admin_regenerate_flatfiles_path, params: {target: 'accessions', numbers: accession,
                                                   date_mode: 'set', date: '2026-07-01'}

    assert_redirected_to admin_regenerate_flatfiles_path
    assert_equal [accession], enqueued_argument('accessions')
    assert_equal accession,   RegenerateFlatfilesRun.sole.numbers
    assert_equal 1,           RegenerateFlatfilesRun.sole.accession_count
  end

  # The dialog disables a button; a disabled button is a courtesy. The
  # rule is here, or the one scope that cannot be taken back is a
  # hand-written POST away.
  test 'the all-submissions scope is refused without the typed phrase' do
    assert_no_enqueued_jobs only: RegenerateSubmissionFlatfilesJob do
      post admin_regenerate_flatfiles_path, params: {target: 'all'}
    end

    assert_redirected_to admin_regenerate_flatfiles_path
    assert_empty RegenerateFlatfilesRun.all
    assert_match(/Type all to confirm/, flash[:alert])
  end

  # A press that would cover nothing is refused rather than recorded: a
  # run of 0 submissions never finishes, and would sit at the top of the
  # history claiming to be in progress for ever.
  test 'a scope that resolves to nothing starts no run' do
    post admin_regenerate_flatfiles_path, params: {target: 'accessions', numbers: 'PRJDB00000'}

    assert_redirected_to admin_regenerate_flatfiles_path
    assert_empty RegenerateFlatfilesRun.all
    assert_match(/Nothing to regenerate/, flash[:alert])
  end

  test 'a retry covers what failed, with the options that failed' do
    accession = named_accession
    previous  = failed_run(target: 'accessions', numbers: accession, locus_date: Date.new(2026, 7, 1))

    post admin_regenerate_flatfiles_path, params: {retry_of: previous.id, date_mode: 'keep', numbers: ''}

    run = RegenerateFlatfilesRun.recent.first

    assert_equal 'retry',  run.target
    assert_equal previous, run.retry_of
    assert_equal 1,        run.total

    # The form had been cleared; the run it is retrying named a date and
    # an accession. What failed is re-run as it was, not as the page
    # happened to look — a retry that dated every entry of the submission
    # would move dates the original deliberately left alone.
    assert_equal Date.new(2026, 7, 1),      run.locus_date
    assert_equal accession,                 run.numbers
    assert_equal Date.new(2026, 7, 1).to_s, enqueued_argument('value')
    assert_equal [accession],               enqueued_argument('accessions')
  end

  # A retry of an every-submission run has no list, and dating every
  # entry is what that run did.
  test 'a retry of an every-submission run still dates every entry' do
    previous = failed_run(target: 'all', locus_date: Date.new(2026, 7, 1))

    post admin_regenerate_flatfiles_path, params: {retry_of: previous.id}

    assert_nil enqueued_argument('accessions')
    assert_nil RegenerateFlatfilesRun.recent.first.numbers
  end

  # Pressed from one submission's Entries tab, where a curator has just
  # retracted an entry. Recorded as being about that submission rather
  # than as a run that named an accession, because that is what the log
  # is read for and what a retry of it should cover.
  test 'a run over one submission is recorded as being about it, and moves no date' do
    st26 = submissions(:st26)

    post admin_regenerate_flatfiles_path, params: {target: 'submission', submission_id: st26.id, date_mode: 'keep'}

    run = RegenerateFlatfilesRun.sole

    assert_equal 'submission', run.target
    assert_equal st26,         run.submission
    assert_equal 1,            run.total

    # The press is about what the file contains. Nothing names whose date
    # would move, so nothing does.
    assert_nil run.locus_date
    assert_nil run.numbers
    assert_nil enqueued_argument('value')
    assert_nil enqueued_argument('accessions')

    # To the run, not to the bulk tool: this curator never went there.
    assert_redirected_to admin_regenerate_flatfiles_run_path(run)
  end

  # The screen sends `keep` in a hidden field, and a hidden field is a
  # courtesy. Without the rule behind it, a hand-written POST would date
  # every entry of the submission — the shape of the incident the
  # disagreement guard exists for.
  test 'a date on the one-submission target is refused' do
    st26 = submissions(:st26)

    assert_no_enqueued_jobs only: RegenerateSubmissionFlatfilesJob do
      post admin_regenerate_flatfiles_path,
           params: {target: 'submission', submission_id: st26.id, date_mode: 'set', date: '2001-01-01'}
    end

    assert_empty RegenerateFlatfilesRun.all
    assert_match(/keeps the LOCUS dates it finds/, flash[:alert])
  end

  # The set a retry covers is "whatever failed", but what it is about is
  # still the submission the run it retries was about — so the log says
  # so, and the curator lands back on it.
  test 'a retry of a one-submission run is still about that submission' do
    st26     = submissions(:st26)
    previous = failed_run(target: 'submission', submission: st26)

    post admin_regenerate_flatfiles_path, params: {retry_of: previous.id}

    run = RegenerateFlatfilesRun.recent.first

    assert_equal 'retry', run.target
    assert_equal st26,    run.submission
    assert_nil            run.locus_date

    assert_redirected_to admin_regenerate_flatfiles_run_path(run)
  end

  # A refusal sends the curator back to the screen they pressed on. The
  # bulk tool is where the press did not come from, and "wait for the run
  # to finish" is not worth being lost over.
  test 'a refused press over one submission goes back to that submission' do
    RegenerateFlatfilesRun.create!(actor: 'admin:someone', target: 'all', total: 10, started_at: 2.minutes.ago)

    post admin_regenerate_flatfiles_path,
         params: {target: 'submission', submission_id: submissions(:st26).id, date_mode: 'keep'}

    assert_redirected_to entries_admin_submission_request_path(submission_requests(:st26))
    assert_match(/still going/, flash[:alert])
  end

  # A BioProject or BioSample submission has no flatfile to rebuild, and
  # a number that names nothing is a typo. Neither starts a run.
  test 'a submission that cannot produce a flatfile starts no run' do
    post admin_regenerate_flatfiles_path,
         params: {target: 'submission', submission_id: submissions(:biosample).id, date_mode: 'keep'}

    assert_empty RegenerateFlatfilesRun.all
    assert_match(/Nothing to regenerate/, flash[:alert])
  end

  # Two runs over one submission would have two workers rewriting one
  # flatfile, both overwriting the LOCUS date and both writing an
  # accession history entry for it.
  test 'a second run is refused while one is in flight' do
    RegenerateFlatfilesRun.create!(actor: 'admin:someone', target: 'all', total: 10, started_at: 2.minutes.ago)

    assert_no_enqueued_jobs only: RegenerateSubmissionFlatfilesJob do
      post admin_regenerate_flatfiles_path, params: {target: 'all', confirm: 'all'}
    end

    assert_equal 1, RegenerateFlatfilesRun.count
    assert_match(/still going/, flash[:alert])
  end

  # Or one dead worker would close the tool for good — the same dead end
  # a BioSample migration run reached in July.
  test 'a run that has stopped reporting does not block a new one' do
    dead = RegenerateFlatfilesRun.create!(actor: 'admin:someone', target: 'all', total: 10, started_at: 5.hours.ago)
    dead.update_columns(updated_at: 5.hours.ago)

    post admin_regenerate_flatfiles_path, params: {target: 'all', confirm: 'all'}

    assert_equal 2, RegenerateFlatfilesRun.count
  end

  # The total is what was enqueued. Counted-then-enqueued leaves a run
  # one short of a total it can never reach if a submission goes away in
  # between, and the screen then reports "Regenerating…" for an hour.
  test 'the total counts what was enqueued' do
    post admin_regenerate_flatfiles_path, params: {target: 'all', confirm: 'all'}

    run = RegenerateFlatfilesRun.sole

    assert_equal 1, run.total
    assert_equal 1, enqueued_jobs.count { it['job_class'] == 'RegenerateSubmissionFlatfilesJob' }
  end

  test 'preview reports the scope without starting anything' do
    assert_no_enqueued_jobs only: RegenerateSubmissionFlatfilesJob do
      post preview_admin_regenerate_flatfiles_path, params: {target: 'all'}
    end

    assert_response :success
    assert_select '[data-test-scope-summary]'
  end

  test 'create returns 403 for non-admin users' do
    sign_in_as users(:carol)

    with_exceptions_app do
      post admin_regenerate_flatfiles_path, params: {target: 'all', confirm: 'all'}
    end

    assert_response :forbidden
  end

  private

  def named_accession = submissions(:st26).entries.first.accession

  # A finished run with one failure to retry, so each test shows only the
  # axis it is about.
  def failed_run(**attrs)
    RegenerateFlatfilesRun.create!(
      actor: 'admin:someone', total: 1, started_at: 1.hour.ago, finished_at: 1.hour.ago, failed: 1, **attrs
    ).tap {
      it.failures.create!(submission: submissions(:st26), label: 'X00001', message: 'boom')
    }
  end

  def enqueued_argument(key)
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { it['job_class'] == 'RegenerateSubmissionFlatfilesJob' }

    job['arguments'].find { it.is_a?(Hash) && it.key?(key) }&.fetch(key)
  end
end
