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

    within '.btn-group' do
      click_link 'BioSample'
    end

    within 'table' do
      assert_text    "##{bs.id}"
      assert_no_text "##{bp.id}"
    end
  end

  # The rule is one run per database, so that is what the screen leads
  # with. A list of runs made the reader reconstruct it, and then the
  # press was refused with an alert saying what the screen already knew.
  test 'each database leads with its own state and its one next move' do
    running = MigrationRun.create!(db: 'bioproject', status: :running, total: 100,
                                   counters: {'created' => 62}, started_at: 10.minutes.ago)

    visit admin_migration_runs_path

    within '[data-test-db-state="bioproject"]' do
      # The badge is capitalised by CSS, so the text node is the enum's.
      assert_text    'running'
      assert_text    '62 of 100 rows'
      assert_text    'last progress'
      assert_link    "Run ##{running.id} →"
      assert_no_link 'Start a run'
    end

    # The other one has nothing running, so it is the one that offers to.
    within '[data-test-db-state="biosample"]' do
      assert_text 'Idle'
      assert_link 'Start a run'
    end
  end

  test 'a database that has run before says how that went' do
    MigrationRun.create!(db: 'biosample', status: :completed, total: 20,
                         counters: {'created' => 17, 'failed' => 3},
                         started_at: 2.days.ago, finished_at: 2.days.ago + 1.hour)

    visit admin_migration_runs_path

    within '[data-test-db-state="biosample"]' do
      assert_text 'Idle'
      assert_text '20 of 20 rows · 3 failed'
    end
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
  # Shown, and disabled, with the reason it cannot be pressed. Hidden, a
  # curator who came back an hour later looked for a control that had
  # never been there.
  test 'a run that is still moving cannot be abandoned, and says why' do
    run = MigrationRun.create!(db: 'biosample', status: :running, started_at: 2.minutes.ago)

    visit admin_migration_run_path(run)

    assert_text     'it last progressed'
    assert_selector 'button[disabled]', text: 'Abandon this run'
  end

  # The counter keys are the job's vocabulary. A table of them is
  # readable only by someone who has read the importer.
  test 'the run detail says what happened to each row in words' do
    run = MigrationRun.create!(db: 'bioproject', status: :completed, total: 30,
                               counters: {'failed' => 2, 'created' => 20, 'skipped' => 8},
                               started_at: 1.hour.ago, finished_at: 30.minutes.ago)

    visit admin_migration_run_path(run)

    within '[data-test-outcomes]' do
      assert_text 'Imported as a new submission'
      assert_text 'Already identical, nothing written'
      assert_text 'Could not be converted'

      # Fixed order rather than sorted by count, so the same run reads
      # the same way twice.
      assert_equal %w[created skipped failed], all('code').map(&:text)
    end
  end

  # One line per row answers "which row" and never "what do I fix".
  test 'rows that did not import are grouped by cause, with the raw log kept underneath' do
    run = MigrationRun.create!(db: 'bioproject', status: :completed, total: 4,
                               counters: {'failed' => 3, 'created' => 1}, started_at: 1.hour.ago)

    run.update!(error_log: [
      '[PSUB000318] KeyError: missing organism',
      '[PSUB000402] KeyError: missing organism',
      '[PSUB000455] ArgumentError: unknown locus tag prefix',
      'ABANDONED: superseded by a new run'
    ].join("\n"))

    visit admin_migration_run_path(run)

    within '[data-test-unimported-groups]' do
      rows = all('tr').map(&:text)

      assert_equal 2, rows.size
      assert_match(/missing organism.*PSUB000318, PSUB000402.*2\z/m, rows.first)
      assert_match(/unknown locus tag prefix.*PSUB000455.*1\z/m,     rows.last)
    end

    # Not a row failure, so it is said as what it is.
    assert_text 'ABANDONED: superseded by a new run'

    # And the log itself is still there for whoever needs it.
    assert_selector 'details', text: 'Show the raw log'

    # The whole list is a download, not three groups and a shrug.
    click_link 'Download the full list'

    assert_equal 3, page.body.lines.size
    assert_match(/\A\[PSUB000318\] KeyError/, page.body)
    assert_no_match(/ABANDONED/, page.body)
  end

  # staging and production have the D-way credentials — the deployed app
  # reads the legacy Postgres through the same one — so "we do not import
  # here" was only ever true while nobody pressed the button. The list
  # stays readable, because the history of what was imported is worth
  # having wherever it happened.
  test 'where importing is switched off, the list reads but nothing starts' do
    DataMigration::DwayDefaults.stub(:enabled?, false) do
      visit admin_migration_runs_path

      within '[data-test-db-state="bioproject"]' do
        assert_text    'switched off'
        assert_no_link 'Start a run'
      end

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

  # The press abandons a run, and the run it abandons has a number. The
  # form used to state the rule ("a run that stopped moving over an hour
  # ago is treated as gone") and leave the reader to work out that it
  # applied to them — which is the general-warning shape this screen is
  # supposed to be past.
  test 'the confirmation names the run that starting would abandon' do
    dead = MigrationRun.create!(db: 'biosample', status: :running, total: 900,
                                counters: {'created' => 412}, started_at: 9.days.ago)
    dead.update_columns(updated_at: 9.days.ago)

    visit new_admin_migration_run_path(db: 'biosample')

    within '[data-test-supersedes="biosample"]' do
      assert_link "##{dead.id}"
      assert_text 'Starting abandons it'

      # What survives it, because "abandoned" reads as "undone" and 412
      # rows are not coming back out.
      assert_text '412 imported rows stay imported'
    end

    # Said against the database it is true of. The radio can still change
    # which one that is, and BioProject has nothing running.
    within '[data-test-db-option="bioproject"]' do
      assert_text 'Nothing is running.'
    end
  end

  # The other half of the same sentence: a live run is not superseded, it
  # refuses. Saying so before the press beats an alert after it.
  test 'the confirmation says when starting would be refused instead' do
    running = MigrationRun.create!(db: 'bioproject', status: :running, started_at: 2.minutes.ago)

    visit new_admin_migration_run_path(db: 'bioproject')

    within '[data-test-blocked-by="bioproject"]' do
      assert_link "##{running.id}"
      assert_text 'Starting is refused'
    end
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
      assert_text 'Submitters notified no'

      assert_link 'Regenerate 1 submission…'
    end
  end

  # Whose dates a date moves is the difference between the two scopes,
  # and it is not readable from the count — both say "1 submission".
  test 'the summary says whose LOCUS dates a date would move' do
    visit admin_regenerate_flatfiles_path(target: 'all', date_mode: 'set', date: '2026-07-01')

    within '[data-test-scope-summary]' do
      assert_text 'LOCUS dates set to 2026-07-01'
      assert_text 'Written to every entry'
    end

    visit admin_regenerate_flatfiles_path(numbers: submissions(:st26).entries.first.accession,
                                          date_mode: 'set', date: '2026-07-01')

    within '[data-test-scope-summary]' do
      assert_text 'Written to the 1 accession named'
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

  # A bulk paste is 127,604 numbers — 1.1 MB in the row — and the only
  # thing that reads it back is a retry. The panel is polled every three
  # seconds for the length of a run and the history lists ten rows at a
  # time, so counting the list on the way out meant detoasting a megabyte
  # and allocating 127,604 strings on every one of those renders, in the
  # process that is also running the jobs.
  test 'the run screens report the count without reading the list back' do
    run = RegenerateFlatfilesRun.create!(actor: 'admin:sato', target: 'accessions', numbers: 'X00001 X00002',
                                         total: 2, regenerated: 2, started_at: 2.days.ago, finished_at: 2.days.ago + 18)

    [admin_regenerate_flatfiles_path, admin_regenerate_flatfiles_run_path(run)].each do |path|
      # Naming the columns rather than SELECT *, and `numbers` not among
      # them — asserting only the absence would pass for a SELECT * too.
      assert_queries_match(/"regenerate_flatfiles_runs"\."actor"/) do
        assert_no_queries_match(/"regenerate_flatfiles_runs"\.\*/) do
          visit path
        end
      end

      assert_text '2 accessions'
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

  # The summary is re-rendered 300 ms after every keystroke, including
  # while a 1.1 MB list is being pasted and while a run holding one is in
  # flight. Both the blocking run it names and the finished runs its
  # estimate is measured from are read on that path.
  test 'the summary is refreshed without reading any accession list back' do
    RegenerateFlatfilesRun.create!(actor: 'admin:sato', target: 'accessions', numbers: 'X00001 X00002',
                                   total: 2, regenerated: 2, started_at: 2.days.ago, finished_at: 2.days.ago + 18)

    RegenerateFlatfilesRun.create!(actor: 'admin:sato', target: 'accessions', numbers: 'X00003',
                                   total: 1, started_at: 1.minute.ago)

    visit admin_regenerate_flatfiles_path

    assert_text 'still going'
    assert_button 'Regenerate 0 submissions', disabled: true

    # Asserting on the count is what makes this wait for the round trip.
    # The blocking warning is already on the page from the first render,
    # so a test that only looked for it would pass without the preview
    # ever being asked.
    assert_no_queries_match(/"regenerate_flatfiles_runs"\.\*/) do
      fill_in 'Accession numbers', with: submissions(:st26).entries.first.accession

      assert_button 'Regenerate 1 submission', disabled: true
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
