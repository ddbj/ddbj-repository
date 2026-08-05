require 'test_helper'

class SampleTSVImportTest < ActiveSupport::TestCase
  setup do
    @submission = submissions(:biosample)
  end

  test 'requires an actor' do
    import = @submission.sample_tsv_imports.build(started_at: Time.current)

    assert_not import.valid?
    assert_includes import.errors[:actor], "can't be blank"
  end

  test 'rejects unknown status' do
    import = @submission.sample_tsv_imports.build(actor: 'alice', status: 'bogus', started_at: Time.current)

    assert_not import.valid?
    assert_includes import.errors[:status], 'is not included in the list'
  end

  test 'loading? matches the running enum value; completed? is its inverse' do
    running = @submission.sample_tsv_imports.create!(
      actor:      'a',
      status:     'running',
      started_at: Time.current
    )
    completed = @submission.sample_tsv_imports.create!(
      actor:      'a',
      status:     'completed',
      started_at: Time.current
    )
    failed = @submission.sample_tsv_imports.create!(
      actor:      'a',
      status:     'failed',
      started_at: Time.current
    )

    assert     running.loading?
    assert_not running.completed?

    assert_not completed.loading?
    assert     completed.completed?

    assert_not failed.loading?
    assert     failed.completed?, 'failed counts as completed so the polling UI does not hang'
  end
end
