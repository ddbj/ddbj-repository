require 'test_helper'

class AdminMigrationRunsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)
  end

  test 'index lists runs and offers only a Database filter' do
    bp = MigrationRun.create!(db: 'bioproject')
    bs = MigrationRun.create!(db: 'biosample')

    get admin_migration_runs_path

    assert_response :ok
    assert_match "##{bp.id}", response.body
    assert_match "##{bs.id}", response.body

    # The list only supports filtering by database. The shared filter
    # partial used to render a user-uid field this controller never
    # honoured; it has been dropped.
    assert_no_match 'User uid', response.body
  end

  test 'index filters by db' do
    bp = MigrationRun.create!(db: 'bioproject')
    bs = MigrationRun.create!(db: 'biosample')

    get admin_migration_runs_path, params: {db: 'biosample'}

    assert_response :ok
    assert_match    "##{bs.id}", response.body
    assert_no_match "##{bp.id}", response.body
  end
end
