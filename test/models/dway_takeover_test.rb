require 'test_helper'

class DwayTakeoverTest < ActiveSupport::TestCase
  test 'is recorded once' do
    DwayTakeover.record!(by: 'alice')

    assert DwayTakeover.done?
    assert_raises(ActiveRecord::RecordNotUnique) { DwayTakeover.record!(by: 'bob') }
  end

  # What D-way would bring back is what this system now decides.
  test 'the import from D-way stops' do
    assert DataMigration::DwayDefaults.enabled?

    DwayTakeover.record!(by: 'alice')

    assert_not DataMigration::DwayDefaults.enabled?

    error = assert_raises(DataMigration::DwayDefaults::Disabled) { DataMigration::DwayDefaults.ensure_enabled! }

    assert_match(/handed over/, error.message)
  end

  test "an imported DRA submission's status is set here" do
    rows = DRASubmission.where(id: dra_submissions(:dra))
    rows.first.submission.update_column :source_id, 'DRA000001'

    assert_empty DRASubmission.settable_statuses_for(rows)

    DwayTakeover.record!(by: 'alice')

    assert_equal DRASubmission.settable_statuses, DRASubmission.settable_statuses_for(rows)
  end
end
