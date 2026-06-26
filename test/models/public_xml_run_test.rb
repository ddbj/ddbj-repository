require 'test_helper'

class PublicXMLRunTest < ActiveSupport::TestCase
  test 'rejects unknown db' do
    run = PublicXMLRun.new(db: 'unknown', kind: 'public', started_at: Time.current)

    assert_not run.valid?
    assert_includes run.errors[:db], 'is not included in the list'
  end

  test 'rejects unknown kind' do
    run = PublicXMLRun.new(db: 'bioproject', kind: 'rubbish', started_at: Time.current)

    assert_not run.valid?
    assert_includes run.errors[:kind], 'is not included in the list'
  end

  test 'rejects exchange kind for biosample' do
    run = PublicXMLRun.new(db: 'biosample', kind: 'exchange', started_at: Time.current)

    assert_not run.valid?
    assert_includes run.errors[:kind], 'exchange is only valid for bioproject'
  end

  test 'allows exchange kind for bioproject' do
    run = PublicXMLRun.new(db: 'bioproject', kind: 'exchange', started_at: Time.current)

    assert run.valid?
  end

  test 'default status is running' do
    run = PublicXMLRun.create!(db: 'bioproject', kind: 'public', started_at: Time.current)

    assert_equal 'running', run.status
    assert run.running_status?
  end

  test 'previous_public_run returns most recent completed public run for the db' do
    PublicXMLRun.create!(db: 'bioproject', kind: 'public',   status: 'completed', started_at: 3.days.ago, finished_at: 3.days.ago + 1.hour)
    target = PublicXMLRun.create!(db: 'bioproject', kind: 'public', status: 'completed', started_at: 1.day.ago,  finished_at: 1.day.ago  + 1.hour)
    PublicXMLRun.create!(db: 'bioproject', kind: 'public',   status: 'failed',    started_at: 1.hour.ago)
    PublicXMLRun.create!(db: 'bioproject', kind: 'exchange', status: 'completed', started_at: 1.hour.ago, finished_at: Time.current)
    PublicXMLRun.create!(db: 'biosample',  kind: 'public',   status: 'completed', started_at: 1.hour.ago, finished_at: Time.current)

    assert_equal target, PublicXMLRun.previous_public_run(db: 'bioproject')
  end

  test 'previous_public_run returns nil when no completed public run exists' do
    assert_nil PublicXMLRun.previous_public_run(db: 'bioproject')
  end
end
