require 'test_helper'

class BioSample::ImporterTest < ActiveSupport::TestCase
  SC = BioSample::StagingClient

  def build(samples_count: 2, ssub_id: 'SSUB-test', user_uid: 'migration-test', migration_run_id: SecureRandom.uuid)
    samples = (1..samples_count).map {|i|
      SC::Sample.new(
        smp_id:        i,
        accession:     "SAMD0009999#{i}",
        sample_name:   "DRS00000#{i}",
        package:       'Generic',
        package_group: nil,
        env_package:   nil,
        status_id:     5500,
        attributes:    [
          {'name' => 'organism',    'value' => 'human gut metagenome'},
          {'name' => 'taxonomy_id', 'value' => '408170'},
          {'name' => 'sample_title', 'value' => "sample-#{i}"}
        ]
      )
    }

    row = SC::Submission.new(
      ssub_id:          ssub_id,
      submitter_id:     user_uid,
      organization:     'Sample Organization',
      organization_url: nil,
      comment:          '[2014] sample import',
      contacts:         [],
      samples:          samples
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
      ssub_id: 'SSUB-empty', submitter_id: 'u', organization: nil, organization_url: nil, comment: nil,
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

  test 'first-import baseline is a single root `add` snapshot that carries volatile fields' do
    # Going through Canonicalizer.diff({}, record) would strip
    # /schema_version, /provenance and /**/accession from both sides
    # → patch chain replay would produce a record SMALLER than the
    # importer cache holds, surfacing as admin show / ?as_of=
    # divergence. Pin the snapshot shape directly.
    result = build(samples_count: 2).call

    assert_equal :created, result.outcome
    assert_equal 1, result.submission.updates.count

    baseline = result.submission.updates.first.parsed_patch
    assert_equal 1,        baseline.size, 'first-import baseline must be a single op'
    assert_equal 'add',    baseline.first['op']
    assert_equal '',       baseline.first['path']

    # Materialise via PURE REPLAY (cache cleared) — must match the
    # cache-backed materialised_record. Catches a regression where
    # the baseline strips volatiles and only the cache happens to
    # hold them.
    result.submission.update_columns(cached_materialised_record: nil, cached_at_update_id: nil)
    replayed = result.submission.reload.materialised_record

    assert_equal 'v3',                                replayed['schema_version']
    assert_equal({'source_format' => 'dway_bs_eav'},  replayed['provenance'])
    assert replayed.key?('samples'),     'samples must be in the materialised replay'
    assert replayed.key?('submission'),  'submission must be in the materialised replay'
  end

  test 're-run with a bag-internal change falls back to a root snapshot (still replayable)' do
    build(samples_count: 2).call

    # Bag-internal change: one sample's title bumped. Canonicalizer.diff
    # would produce `replace /samples/0/title`, which descends into the
    # `samples` bag → BagPatchPathError → importer falls back to a
    # whole-record snapshot at root. The chain stays replayable; we
    # just lose per-field granularity for this op.
    bumped = SC::Submission.new(
      ssub_id: 'SSUB-test', submitter_id: 'migration-test',
      organization: 'Sample Organization', organization_url: nil,
      comment: '[2014] sample import', contacts: [],
      samples: [
        SC::Sample.new(smp_id: 1, accession: 'SAMD00099991', sample_name: 'DRS000001', package: 'Generic',
                       package_group: nil, env_package: nil, status_id: 5500, attributes: [
                         {'name' => 'organism',     'value' => 'human gut metagenome'},
                         {'name' => 'taxonomy_id',  'value' => '408170'},
                         {'name' => 'sample_title', 'value' => 'sample-1 BUMPED'}
                       ]),
        SC::Sample.new(smp_id: 2, accession: 'SAMD00099992', sample_name: 'DRS000002', package: 'Generic',
                       package_group: nil, env_package: nil, status_id: 5500, attributes: [
                         {'name' => 'organism',     'value' => 'human gut metagenome'},
                         {'name' => 'taxonomy_id',  'value' => '408170'},
                         {'name' => 'sample_title', 'value' => 'sample-2'}
                       ])
      ]
    )

    result = BioSample::Importer.new(staging_submission: bumped, user_uid: 'migration-test', migration_run_id: SecureRandom.uuid).call

    assert_equal :updated, result.outcome
    assert_equal 2,        result.submission.updates.count

    second_patch = result.submission.updates.order(:id).last.parsed_patch
    assert_equal 1, second_patch.size, 'fallback should be a single root op'
    assert_equal '',         second_patch.first['path']
    assert_equal 'replace',  second_patch.first['op'],
                 'second-run fallback should be `replace`, not `add` (prior chain is non-empty)'

    # Replay correctness — exact set must materialise; the snapshot
    # must REPLACE (not add) sample-2 alongside sample-1.
    titles = result.submission.materialised_record['samples'].map {|s| s['title'] }.sort
    assert_equal ['sample-1 BUMPED', 'sample-2'], titles
  end

  test ':skipped re-run still stamps migration_run_id so a bad-batch rollback selector catches typed-column drift' do
    first_run_id = SecureRandom.uuid
    BioSample::Importer.new(staging_submission: build.instance_variable_get(:@row),
                            user_uid:         'migration-test',
                            migration_run_id: first_run_id).call

    second_run_id = SecureRandom.uuid
    result = BioSample::Importer.new(staging_submission: build.instance_variable_get(:@row),
                                     user_uid:         'migration-test',
                                     migration_run_id: second_run_id).call

    assert_equal :skipped, result.outcome
    # sync_samples! ran in this run, so the rollback selector
    # Submission.where(migration_run_id: second_run_id).destroy_all
    # MUST pick this row up; otherwise typed-column drift survives
    # the rollback.
    assert_equal second_run_id, result.submission.reload.migration_run_id
  end

  test 'compute_patch_ops falls back to root snapshot when Canonicalizer.diff raises ANY Canonicalizer::Error (not just bag descent)' do
    submission = submissions(:biosample)
    submission.append_update!({'project' => {'title' => 'good'}}, actor: 'test')
    record     = {'project' => {'title' => 'irrelevant'}}

    importer = BioSample::Importer.new(staging_submission: build.instance_variable_get(:@row),
                                       user_uid:         'migration-test',
                                       migration_run_id: SecureRandom.uuid)

    DDBJRecord::Canonicalizer.stub(:diff, ->(*) { raise DDBJRecord::Canonicalizer::ControlCharacterError, 'simulated' }) do
      ops = importer.send(:compute_patch_ops, {'project' => {'title' => 'prior'}}, record)

      assert_equal 1,         ops.size
      assert_equal '',        ops.first['path']
      assert_equal 'replace', ops.first['op']
      assert_equal record,    ops.first['value']
    end
  end

  test 'rejects cross-user re-attribution' do
    build(user_uid: 'first-user').call

    assert_raises BioSample::Importer::CrossUserError do
      build(user_uid: 'second-user').call
    end
  end

  test 'syncs samples by position, supporting nil-accession drafts' do
    drafts = [
      SC::Sample.new(smp_id: 10, accession: nil, sample_name: 'DRS_DRAFT_A', package: 'Generic', package_group: nil, env_package: nil, status_id: 5400, attributes: []),
      SC::Sample.new(smp_id: 11, accession: nil, sample_name: 'DRS_DRAFT_B', package: 'Generic', package_group: nil, env_package: nil, status_id: 5500, attributes: [])
    ]
    row = SC::Submission.new(
      ssub_id: 'SSUB-nil-acc', submitter_id: 'u', organization: nil, organization_url: nil, comment: nil,
      contacts: [], samples: drafts
    )

    result = BioSample::Importer.new(staging_submission: row, user_uid: 'u', migration_run_id: SecureRandom.uuid).call

    assert_equal :created, result.outcome
    assert_equal 2, result.submission.samples.count

    by_name = result.submission.samples.order(:id).index_by(&:sample_name)
    assert_equal 'private', by_name['DRS_DRAFT_A'].status, 'each draft must keep its own status_id'
    assert_equal 'public',  by_name['DRS_DRAFT_B'].status
  end

  test 'sync_samples drops trailing Sample rows removed from the staging snapshot' do
    build(samples_count: 3).call
    submission = Submission.find_by(source_id: 'SSUB-test')
    assert_equal 3, submission.samples.count

    # Same psub_id but with only 2 samples now (third removed in D-way).
    smaller = (1..2).map {|i|
      SC::Sample.new(
        smp_id: i, accession: "SAMD0009999#{i}", sample_name: "DRS00000#{i}",
        package: 'Generic', package_group: nil, env_package: nil, status_id: 5500,
        attributes: [{'name' => 'organism', 'value' => 'sample organism'}]
      )
    }
    row = SC::Submission.new(
      ssub_id: 'SSUB-test', submitter_id: 'migration-test', organization: nil, organization_url: nil, comment: nil,
      contacts: [], samples: smaller
    )

    BioSample::Importer.new(staging_submission: row, user_uid: 'migration-test', migration_run_id: SecureRandom.uuid).call

    assert_equal 2, submission.samples.reload.count
    refute submission.samples.exists?(accession: 'SAMD00099993'), 'trailing row must be destroyed'
  end

  test ':skipped re-run re-stamps migration_run_id (sync_samples! ran) and always re-syncs Sample typed columns from staging' do
    # Sample typed columns include staging-only fields (package_group,
    # env_package) that never reach the canonical patch, so gating
    # sync on patch-equality would permanently strand staging updates.
    # Because sync_samples! DID write on this run, migration_run_id is
    # re-stamped so the bad-batch rollback selector
    #   Submission.where(migration_run_id: 'R-bad').destroy_all
    # picks the row up. canonical_version / converter_version stay
    # frozen because the chain itself didn't change. Trade-off:
    # curator edits to typed columns survive only until the next
    # re-import. Documented in BioSample::Importer's docstring.
    importer = build
    first    = importer.call.submission

    travel 1.second
    sample = first.samples.first
    sample.update!(title: 'Curator-edited title')

    second_run_id = SecureRandom.uuid
    second        = build(migration_run_id: second_run_id).call
    assert_equal :skipped, second.outcome
    submission = second.submission.reload

    # migration_run_id MUST be re-stamped — sync_samples! wrote, so a
    # rollback selector must catch this row.
    assert_equal second_run_id, submission.migration_run_id

    # Sample typed columns re-synced from staging; curator edit lost.
    assert_equal 'sample-1', sample.reload.title
  end

  test 'staging-only typed columns (package_group / env_package) backfill on re-run even when patch is byte-identical' do
    # Initial run: staging row has NULL package_group / env_package.
    samples = [SC::Sample.new(
      smp_id: 1, accession: 'SAMD00099991', sample_name: 'DRS001',
      package: 'Generic', package_group: nil, env_package: nil,
      status_id: 5500, attributes: []
    )]
    row = SC::Submission.new(
      ssub_id: 'SSUB-typed-backfill', submitter_id: 'u', organization: nil, organization_url: nil,
      comment: nil, contacts: [], samples: samples
    )
    BioSample::Importer.new(staging_submission: row, user_uid: 'u', migration_run_id: SecureRandom.uuid).call

    sample = Submission.find_by(source_id: 'SSUB-typed-backfill').samples.first
    assert_nil sample.package_group
    assert_nil sample.env_package

    # Re-run after staging side fills the typed columns. Canonical
    # patch is byte-identical (package_group/env_package never reach
    # the v3 record), so :skipped fires — but sync_samples must still
    # backfill the typed columns from staging.
    row_updated = SC::Submission.new(
      ssub_id: 'SSUB-typed-backfill', submitter_id: 'u', organization: nil, organization_url: nil,
      comment: nil, contacts: [],
      samples: [SC::Sample.new(
        smp_id: 1, accession: 'SAMD00099991', sample_name: 'DRS001',
        package: 'Generic', package_group: 'MIGS.ba', env_package: 'soil',
        status_id: 5500, attributes: []
      )]
    )
    result = BioSample::Importer.new(staging_submission: row_updated, user_uid: 'u', migration_run_id: SecureRandom.uuid).call

    assert_equal :skipped, result.outcome
    sample.reload
    assert_equal 'MIGS.ba', sample.package_group
    assert_equal 'soil',    sample.env_package
  end

  test 'maps unknown status_id to :curating' do
    samples = [SC::Sample.new(
      smp_id: 1, accession: 'SAMD00099991', sample_name: 'DRS001',
      package: 'Generic', package_group: nil, env_package: nil, status_id: 99_999, attributes: []
    )]
    row = SC::Submission.new(
      ssub_id: 'SSUB-status', submitter_id: 'u', organization: nil, organization_url: nil, comment: nil,
      contacts: [], samples: samples
    )

    result = BioSample::Importer.new(staging_submission: row, user_uid: 'u', migration_run_id: SecureRandom.uuid).call

    assert_equal 'curating', result.submission.samples.first.status
  end

  test 'lifts staging package_group + env_package into Sample typed columns' do
    samples = [
      SC::Sample.new(
        smp_id:        1,
        accession:     'SAMD00099991',
        sample_name:   'DRS001',
        package:       'MIGS.ba.soil.6.0',
        package_group: 'MIGS.ba',
        env_package:   'soil',
        status_id:     5500,
        attributes:    []
      ),
      SC::Sample.new(
        smp_id:        2,
        accession:     'SAMD00099992',
        sample_name:   'DRS002',
        package:       'Generic.1.0',
        package_group: nil,
        env_package:   nil,
        status_id:     5500,
        attributes:    []
      )
    ]
    row = SC::Submission.new(
      ssub_id: 'SSUB-pkg', submitter_id: 'u', organization: nil, organization_url: nil, comment: nil,
      contacts: [], samples: samples
    )

    result = BioSample::Importer.new(staging_submission: row, user_uid: 'u', migration_run_id: SecureRandom.uuid).call

    by_acc = result.submission.samples.index_by(&:accession)
    assert_equal 'MIGS.ba', by_acc['SAMD00099991'].package_group
    assert_equal 'soil',    by_acc['SAMD00099991'].env_package
    assert_nil              by_acc['SAMD00099992'].package_group
    assert_nil              by_acc['SAMD00099992'].env_package
  end
end
