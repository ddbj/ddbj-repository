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
  end

  # Three states, each of which has to say something different — and the
  # page has to stop polling itself once there is nothing left to watch.
  test 'a run that has not started says nothing is running' do
    visit admin_regenerate_flatfiles_path

    assert_text    'Regenerate Flatfiles'
    assert_no_text 'Processing:'
    assert_no_selector '[data-controller="auto-refresh"]'
  end

  test 'a run in progress reports its count and refreshes itself' do
    RegenerateFlatfilesProgress.create!(total: 10, processed: 3)

    visit admin_regenerate_flatfiles_path

    assert_text 'Processing: 3 succeeded'
    assert_selector '[data-controller="auto-refresh"]'
  end

  test 'a finished run reports when it finished, and stops refreshing' do
    progress = RegenerateFlatfilesProgress.create!(total: 5, processed: 5)

    visit admin_regenerate_flatfiles_path

    assert_text "Completed at #{progress.updated_at.strftime('%Y-%m-%d %H:%M')}"
    assert_text '5 succeeded.'
    assert_no_selector '[data-controller="auto-refresh"]'
  end

  # Failures still count towards done, or a run with one bad submission
  # would poll for ever.
  test 'a run finishes even when some of it failed' do
    RegenerateFlatfilesProgress.create!(total: 10, processed: 7, failed: 3)

    visit admin_regenerate_flatfiles_path

    assert_text 'Completed at'
    assert_text '7 succeeded, 3 failed'
    assert_no_selector '[data-controller="auto-refresh"]'
  end
end
