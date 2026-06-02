require 'test_helper'

class SubmissionTest < ActiveSupport::TestCase
  test '#materialised_record returns nil before any update is appended' do
    submission = submissions(:bioproject)

    assert_nil submission.materialised_record
  end

  test '#materialised_record replays a single baseline patch into the full v3 hash' do
    submission = submissions(:bioproject)
    record     = {
      'schema_version' => 'v3',
      'project'        => {'accession' => 'PRJDB502', 'title' => 'sample'}
    }
    baseline = [{'op' => 'add', 'path' => '', 'value' => record}]

    submission.updates.create!(
      db:                      'bioproject',
      status:                  'applied',
      actor:                   'migration',
      source:                  'migration',
      patch:                   Oj.dump(baseline, mode: :strict),
      patch_canonical_version: DDBJRecord::Canonicalizer::VERSION
    )

    assert_equal record, submission.materialised_record
  end

  test '#materialised_record replays a chain of patches in id order' do
    submission = submissions(:bioproject)

    baseline = [{'op' => 'add', 'path' => '', 'value' => {'project' => {'title' => 'first'}}}]
    edit     = [{'op' => 'replace', 'path' => '/project/title', 'value' => 'second'}]

    [baseline, edit].each do |patch|
      submission.updates.create!(
        db:                      'bioproject',
        status:                  'applied',
        actor:                   'migration',
        source:                  'migration',
        patch:                   Oj.dump(patch, mode: :strict),
        patch_canonical_version: DDBJRecord::Canonicalizer::VERSION
      )
    end

    assert_equal 'second', submission.materialised_record.dig('project', 'title')
  end

  test '#materialised_record raises MaterialisationFailed carrying the offending update_id' do
    submission = submissions(:bioproject)
    bad_update = submission.updates.create!(
      db:                      'bioproject',
      status:                  'applied',
      actor:                   'test',
      source:                  'manual',
      patch:                   'not-json-at-all',
      patch_canonical_version: 1
    )

    error = assert_raises(Submission::MaterialisationFailed) do
      submission.materialised_record
    end

    assert_equal bad_update.id, error.update_id
    assert_kind_of Oj::ParseError, error.original
  end
end
