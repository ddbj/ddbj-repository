require 'test_helper'

class SubmissionUpdateTest < ActiveSupport::TestCase
  test 'requires non-empty patch via model validation' do
    update = SubmissionUpdate.new(submission: submissions(:st26), db: :st26, source: :migration, patch: '')

    assert_not update.valid?
    assert_includes update.errors[:patch], 'is too short (minimum is 1 character)'
  end

  test 'database CHECK constraint rejects empty patch when validation is bypassed' do
    assert_raises ActiveRecord::StatementInvalid do
      SubmissionUpdate.connection.execute(<<~SQL.squish)
        INSERT INTO submission_updates (submission_id, db, source, patch, created_at, updated_at)
        VALUES (#{submissions(:st26).id}, 'st26', 0, ''::bytea, NOW(), NOW())
      SQL
    end
  end

  test 'source enum exposes migration / manual / batch / tsv_import' do
    update = submission_updates(:st26)

    assert update.migration?
    assert_equal({'manual' => 0, 'migration' => 1, 'batch' => 2, 'tsv_import' => 3}, SubmissionUpdate.sources)
  end

  test 'roundtrips arbitrary patch bytes including null bytes' do
    raw    = '[{"op":"replace","path":"/x","value":" "}]'
    update = SubmissionUpdate.create!(submission: submissions(:st26), db: :st26, source: :manual, patch: raw)

    assert_equal raw, update.reload.patch
  end

  test '#parsed_patch / #op_count are PUBLIC (admin show view calls them externally)' do
    update = submission_updates(:st26)

    # Bare callable check — NoMethodError 'private method called for ...'
    # is what the admin show view would catch and render as "patch
    # unreadable". The view calls update.parsed_patch on an external
    # receiver, so private-by-accident is a UX regression.
    assert update.public_methods.include?(:parsed_patch),
           '#parsed_patch must be public — admin show view depends on external call'
    assert update.public_methods.include?(:op_count),
           '#op_count must be public — admin show view depends on external call'
  end
end
