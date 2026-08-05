require 'application_system_test_case'

# The two Tools screens that are lists of state rather than places to
# work: what a migration run shows, and what a regeneration run says
# about itself while it is running and once it has stopped.
class MigrationRunsSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)
  end

  test 'the list shows every run and narrows to one database' do
    bp = MigrationRun.create!(db: 'bioproject')
    bs = MigrationRun.create!(db: 'biosample')

    visit admin_migration_runs_path

    assert_text "##{bp.id}"
    assert_text "##{bs.id}"

    # Only a database filter: the shared partial used to render a user
    # uid field this screen never honoured.
    assert_no_field 'User uid'

    select 'BioSample', from: 'Database'
    click_button 'Filter'

    assert_text    "##{bs.id}"
    assert_no_text "##{bp.id}"
  end

  # A run whose worker died keeps its status for ever, and the enqueue
  # precheck then blocks every future import of that database — the same
  # dead end the precheck exists to prevent, reached from the other side.
  # A BioSample run left running on 22 July did exactly this.
  test 'a run whose worker is gone can be abandoned from the screen' do
    run = MigrationRun.create!(db: 'biosample', status: :running, started_at: 9.days.ago)
    run.update_columns(updated_at: 9.days.ago)

    visit admin_migration_run_path(run)

    assert_text 'last progress 9d ago'

    click_button 'Abandon this run'

    assert_text 'abandoned'
    assert_predicate run.reload, :failed_status?
    assert_match(/ABANDONED/, run.error_log)
  end

  # Abandoning a live run would put a second worker on the same database,
  # and the two would write over each other. "It looks stuck" is not
  # enough — it has to have stopped.
  test 'a run that is still moving cannot be abandoned' do
    run = MigrationRun.create!(db: 'biosample', status: :running, started_at: 2.minutes.ago)

    visit admin_migration_run_path(run)

    assert_text      'Still progressing'
    assert_no_button 'Abandon this run'
  end

  # staging and production have the D-way credentials — the deployed app
  # reads the legacy Postgres through the same one — so "we do not import
  # here" was only ever true while nobody pressed the button. The list
  # stays readable, because the history of what was imported is worth
  # having wherever it happened.
  test 'where importing is switched off, the list reads but nothing starts' do
    DataMigration::DwayDefaults.stub(:enabled?, false) do
      visit admin_migration_runs_path

      assert_selector '[data-test-migration-disabled]'
      assert_no_link  'New run'

      visit new_admin_migration_run_path

      assert_text 'switched off'
      assert_no_button 'Enqueue'
    end
  end

  # The rule, as opposed to the courtesy: every import path opens one of
  # these, including a rake task and a console.
  test 'the D-way connection itself is refused where importing is off' do
    DataMigration::DwayDefaults.stub(:enabled?, false) do
      assert_raises DataMigration::DwayDefaults::Disabled do
        BioProject::StagingClient.new
      end

      assert_raises DataMigration::DwayDefaults::Disabled do
        BioSample::StagingClient.new
      end
    end
  end

  # Belt and braces for the run nobody thought to abandon: starting a new
  # one closes out the abandoned predecessor rather than being refused by
  # it, and says so in that run's log.
  test 'starting a new run supersedes a dead one instead of being blocked by it' do
    dead = MigrationRun.create!(db: 'biosample', status: :running, started_at: 9.days.ago)
    dead.update_columns(updated_at: 9.days.ago)

    visit new_admin_migration_run_path

    choose 'BioSample'
    click_button 'Enqueue'

    assert_predicate dead.reload, :failed_status?
    assert_match(/superseded/, dead.error_log)
    assert_equal 2, MigrationRun.where(db: 'biosample').count
  end
end

class RegenerateFlatfilesSystemTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:bob)

    submissions(:st26).ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )
  end

  # The scope is the whole point of the screen: what it covers has to be
  # readable before it is pressed, not in the flash afterwards.
  test 'the summary counts the scope and names the button after it' do
    visit admin_regenerate_flatfiles_path(target: 'all')

    within '[data-test-scope-summary]' do
      assert_text '1 submission'
      assert_text 'every ST.26 submission with a stored record'
      assert_text 'LOCUS dates unchanged'
      assert_text 'Identical flatfiles skipped'
      assert_text 'Submitters notified no'

      assert_link 'Regenerate 1 submission…'
    end
  end

  # Nothing typed is not a scope. It used to be the widest one there is.
  test 'an empty form offers no press' do
    visit admin_regenerate_flatfiles_path

    within '[data-test-scope-summary]' do
      assert_text     'Nothing to regenerate.'
      assert_selector 'input[type=submit][disabled]'
    end
  end

  # A number that names a BioProject is not a typo — it names a record
  # this tool has no renderer for, and saying so is the difference
  # between "check your input" and "this cannot be done yet".
  test 'numbers that cannot be regenerated are named, not silently dropped' do
    projects(:primary).update!(accession: 'PRJDB19940')

    visit admin_regenerate_flatfiles_path(numbers: "PRJDB19940\nX99999")

    within '[data-test-scope-summary]' do
      assert_text '1 number matched no submission: X99999'
      assert_text 'No flatfile for 1 number — BioProject and BioSample records have none: PRJDB19940'
    end
  end

  test 'a run in progress reports its count and refreshes itself' do
    run = RegenerateFlatfilesRun.create!(actor: 'admin:bob', target: 'all', total: 10, regenerated: 3,
                                         started_at: 2.minutes.ago)

    visit admin_regenerate_flatfiles_run_path(run)

    assert_text     '3 done'
    assert_text     'of 10'
    assert_selector '[data-controller="auto-refresh"]'
  end

  # Three counts, not two: with the rewrite option off, "how many did
  # nothing" is the reading of the run.
  test 'a finished run reports what it changed, what it skipped, and stops refreshing' do
    run = RegenerateFlatfilesRun.create!(actor: 'admin:bob', target: 'all', total: 10, regenerated: 7, skipped: 3,
                                         started_at: 1.hour.ago, finished_at: 30.minutes.ago)

    visit admin_regenerate_flatfiles_run_path(run)

    assert_text        '7 regenerated'
    assert_text        '3 unchanged, skipped'
    assert_text        '0 failed'
    assert_no_selector '[data-controller="auto-refresh"]'
  end

  # The failure is read here, with the accession and the reason, rather
  # than in the job queue.
  test 'a run with failures shows what failed and offers to retry those' do
    run = RegenerateFlatfilesRun.create!(actor: 'admin:bob', target: 'all', total: 2, regenerated: 1, failed: 1,
                                         started_at: 1.hour.ago, finished_at: 30.minutes.ago)

    run.failures.create!(submission: submissions(:st26), label: 'PRJDB18220',
                         message: 'Converter raised: unknown feature key misc_RNA')

    visit admin_regenerate_flatfiles_run_path(run)

    assert_text 'Finished with 1 failure'
    assert_text 'PRJDB18220'
    assert_text 'unknown feature key misc_RNA'
    assert_link 'Download the list'

    click_button 'Retry the 1 failed'

    retried = RegenerateFlatfilesRun.recent.first

    assert_equal 'retry', retried.target
    assert_equal run,     retried.retry_of
  end

  # A run that has gone quiet stops being polled, and stops there. It is
  # not declared over: its jobs may be queued behind something long, and
  # "the workers are gone, run it again" would put a second worker on
  # every submission the first is still holding.
  test 'a run that stops reporting stops being polled, without being declared over' do
    run = RegenerateFlatfilesRun.create!(actor: 'admin:bob', target: 'all', total: 10, regenerated: 4,
                                         started_at: 5.hours.ago)
    run.update_columns(updated_at: 5.hours.ago)

    visit admin_regenerate_flatfiles_run_path(run)

    assert_text        'Not reporting'
    assert_text        'Nothing has been reported since'
    assert_no_text     'Finished'
    assert_no_selector '[data-controller="auto-refresh"]'
  end

  # One run at a time: two over the same submission would have two
  # workers rewriting one flatfile.
  test 'the press is withheld while a run is in flight' do
    RegenerateFlatfilesRun.create!(actor: 'admin:sato', target: 'all', total: 10, regenerated: 4,
                                   started_at: 2.minutes.ago)

    visit admin_regenerate_flatfiles_path(target: 'all')

    within '[data-test-scope-summary]' do
      assert_text     'is still going'
      assert_text     '4 of 10 done'
      assert_selector 'input[type=submit][disabled]'
      assert_no_link  'Regenerate 1 submission…'
    end
  end

  # "When did someone last regenerate everything?" used to have no
  # answer: the tool kept one progress row, overwritten by the next press.
  #
  # The newest run is the panel rather than a row, because the panel keeps
  # itself up to date and the table does not — two readings of the same
  # run disagreeing about whether it has finished is worse than one.
  test 'earlier runs are listed with their scope, actor and outcome' do
    RegenerateFlatfilesRun.create!(actor: 'admin:sato', target: 'accessions', numbers: 'X00001 X00002',
                                   total: 2, regenerated: 2, started_at: 2.days.ago, finished_at: 2.days.ago + 18)

    RegenerateFlatfilesRun.create!(actor: 'admin:bob', target: 'all', total: 1, regenerated: 1,
                                   started_at: 1.minute.ago, finished_at: Time.current)

    visit admin_regenerate_flatfiles_path

    within '[data-test-run-history]' do
      assert_text    '2 accessions'
      assert_text    'sato'
      assert_text    'all succeeded'
      assert_no_text 'All submissions'
    end

    within '[data-test-run-result]' do
      assert_text 'All submissions'
    end
  end
end

# The parts of the screen that only exist once JavaScript is running: the
# summary following the field, and the lock on the one scope that cannot
# be taken back.
class RegenerateFlatfilesJavaScriptTest < JavaScriptSystemTestCase
  setup do
    sign_in_as users(:bob)

    submissions(:st26).ddbj_record.attach(
      io:           file_fixture('ddbj_record/example.json').open,
      filename:     'example.json',
      content_type: 'application/json'
    )
  end

  # With the forgery check running, because that is the half this cannot
  # be trusted to get right on its own: the preview is a POST outside the
  # form's own action, so the form's per-action token does not verify it
  # and the summary would silently stop following the fields.
  test 'the summary follows the scope being chosen' do
    with_forgery_protection do
      visit admin_regenerate_flatfiles_path

      assert_text 'Nothing to regenerate.'

      choose 'Every submission with a stored record'

      assert_text 'every ST.26 submission with a stored record'
      assert_link 'Regenerate 1 submission…'
    end
  end

  # Filling in a date is choosing to set one. Left to the radio alone it
  # is discarded, and the only sign is a summary line saying the dates
  # are unchanged.
  test 'entering a LOCUS date chooses to set it' do
    visit admin_regenerate_flatfiles_path(target: 'all')

    fill_in 'LOCUS date', with: '2026-09-01'

    assert_text 'set to 2026-09-01'
    assert_link 'Regenerate 1 submission…'
  end

  test 'regenerating everything is locked until the phrase is typed' do
    visit admin_regenerate_flatfiles_path(target: 'all')

    click_link 'Regenerate 1 submission…'

    within '[data-test-confirm]' do
      assert_text 'Regenerate every flatfile?'
      assert_selector 'input[type=submit][disabled]'

      fill_in 'confirm', with: 'all'

      assert_no_selector 'input[type=submit][disabled]'

      click_button 'Regenerate 1 submission'
    end

    assert_equal 'all', RegenerateFlatfilesRun.sole.target
  end
end
