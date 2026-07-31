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
