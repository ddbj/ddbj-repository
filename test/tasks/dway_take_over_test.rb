require 'test_helper'
require 'rake'

class DwayTakeOverTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?('dway:take_over')
    Rake::Task['dway:take_over'].reenable
  end

  def run_task(stopped: 'yes', by: 'bob')
    env = {'DWAY_STOPPED' => stopped, 'TAKEN_OVER_BY' => by}
    was = env.keys.index_with { ENV[it] }

    env.each { ENV[_1] = _2 }

    capture_io { Rake::Task['dway:take_over'].invoke }
  ensure
    was.each { ENV[_1] = _2 }
    Rake::Task['dway:take_over'].reenable
  end

  test 'refuses until DRA numbers are taken over, since it reads them from D-way' do
    assert_raises(SystemExit) { run_task }

    assert_not DwayTakeover.done?
  end

  test 'refuses while an import is under way' do
    take_over_dra_numbering
    MigrationRun.create!(db: 'bioproject', status: :running)

    assert_raises(SystemExit) { run_task }

    assert_not DwayTakeover.done?
  end

  test 'records it, once said by a curator' do
    take_over_dra_numbering

    assert_raises(SystemExit) { run_task(by: 'alice') }
    assert_raises(SystemExit) { run_task(stopped: nil) }

    run_task

    assert_equal 'bob', DwayTakeover.sole.taken_over_by
  end
end
