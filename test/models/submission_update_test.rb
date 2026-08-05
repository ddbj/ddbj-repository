require 'test_helper'

class SubmissionUpdateTest < ActiveSupport::TestCase
  test 'requires a patch attachment via model validation' do
    update = SubmissionUpdate.new(submission: submissions(:st26), db: :st26, source: :migration)

    assert_not update.valid?
    assert_includes update.errors[:patch], "can't be blank"
  end

  test 'rejects an empty patch attachment (defence in depth for the dropped bytea CHECK)' do
    update = SubmissionUpdate.new(submission: submissions(:st26), db: :st26, source: :migration)
    update.patch.attach(io: StringIO.new(''), filename: 'empty.json', content_type: 'application/json')

    assert_not update.valid?
    assert_includes update.errors[:patch], 'must not be empty'
  end

  test 'source enum exposes migration / manual / batch / tsv_import' do
    update = submission_updates(:st26)

    assert update.migration?
    assert_equal({'manual' => 0, 'migration' => 1, 'batch' => 2, 'tsv_import' => 3}, SubmissionUpdate.sources)
  end

  test '.create_with_patch! attaches the patch JSON in a single transactional save' do
    raw    = '[{"op":"replace","path":"/x","value":" "}]'
    update = SubmissionUpdate.create_with_patch!(
      submission: submissions(:st26),
      patch_json: raw,
      db:         :st26,
      source:     :manual
    )

    assert update.patch.attached?
    assert_equal raw, update.patch.download
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
