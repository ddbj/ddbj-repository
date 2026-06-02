require 'test_helper'

class BioSample::ImporterTest < ActiveSupport::TestCase
  SC = BioSample::StagingClient

  def build(samples_count: 2, ssub_id: 'SSUB-test', user_uid: 'migration-test', migration_run_id: SecureRandom.uuid)
    samples = (1..samples_count).map {|i|
      SC::Sample.new(
        smp_id:      i,
        accession:   "SAMD0009999#{i}",
        sample_name: "DRS00000#{i}",
        package:     'Generic',
        status_id:   5500,
        attributes:  [
          {'name' => 'organism',    'value' => 'human gut metagenome'},
          {'name' => 'taxonomy_id', 'value' => '408170'},
          {'name' => 'sample_title', 'value' => "sample-#{i}"}
        ]
      )
    }

    row = SC::Submission.new(
      ssub_id:      ssub_id,
      submitter_id: user_uid,
      organization: 'Sample Organization',
      comment:      '[2014] sample import',
      contacts:     [],
      samples:      samples
    )

    BioSample::Importer.new(staging_submission: row, user_uid: user_uid, migration_run_id: migration_run_id)
  end

  test 'creates Submission + N Sample rows + baseline SubmissionUpdate' do
    result = build(samples_count: 3).call

    assert_equal :created, result.outcome
    submission = result.submission
    assert_equal 'biosample', submission.db
    assert_equal 'SSUB-test', submission.source_id
    assert_equal 3,           submission.samples.count
    assert_equal 1,           submission.updates.count

    sample = submission.samples.find_by(accession: 'SAMD00099991')
    assert_equal 'DRS000001',            sample.sample_name
    assert_equal 'public',               sample.status
    assert_equal 'Generic',              sample.package
    assert_equal 408170,                 sample.taxonomy_id
    assert_equal 'human gut metagenome', sample.organism
    assert_equal 'sample-1',             sample.title
  end

  test 'returns :no_samples (no writes) when the staging submission has none' do
    row = SC::Submission.new(
      ssub_id: 'SSUB-empty', submitter_id: 'u', organization: nil, comment: nil,
      contacts: [], samples: []
    )

    result = BioSample::Importer.new(staging_submission: row, user_uid: 'u', migration_run_id: SecureRandom.uuid).call

    assert_equal :no_samples, result.outcome
    assert_nil   Submission.find_by(source_id: 'SSUB-empty')
  end

  test 're-run with identical staging snapshot is :skipped' do
    importer = build
    importer.call

    second = build.call
    assert_equal :skipped, second.outcome
    assert_equal 1,        second.submission.updates.count
  end

  test 'rejects cross-user re-attribution' do
    build(user_uid: 'first-user').call

    assert_raises BioSample::Importer::CrossUserError do
      build(user_uid: 'second-user').call
    end
  end

  test 'maps unknown status_id to :curating' do
    samples = [SC::Sample.new(
      smp_id: 1, accession: 'SAMD00099991', sample_name: 'DRS001',
      package: 'Generic', status_id: 99_999, attributes: []
    )]
    row = SC::Submission.new(
      ssub_id: 'SSUB-status', submitter_id: 'u', organization: nil, comment: nil,
      contacts: [], samples: samples
    )

    result = BioSample::Importer.new(staging_submission: row, user_uid: 'u', migration_run_id: SecureRandom.uuid).call

    assert_equal 'curating', result.submission.samples.first.status
  end
end
