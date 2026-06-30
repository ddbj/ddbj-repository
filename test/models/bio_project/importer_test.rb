require 'test_helper'

class BioProject::ImporterTest < ActiveSupport::TestCase
  XML_FIXTURE = Rails.root.join('test/fixtures/files/data_migration/bio_project/PSUB000604.xml').freeze

  def build(**overrides)
    BioProject::Importer.new(
      psub_id:          'PSUB000604',
      xml:              File.read(XML_FIXTURE),
      user_uid:         'migration-test',
      project_type:     'primary',
      accession:        'PRJDB502', # mirrors staging.project.project_id_prefix||counter for PSUB000604
      migration_run_id: SecureRandom.uuid,
      **overrides
    )
  end

  test 'first-import baseline is a single root `add` snapshot that carries volatile fields' do
    # Going through Canonicalizer.diff({}, record) would strip
    # /schema_version, /provenance and /**/accession from both sides
    # → patch chain replay would produce a record SMALLER than the
    # importer cache holds, surfacing as admin show / ?as_of=
    # divergence. Pin the snapshot shape directly.
    result = build.call

    assert_equal :created, result.outcome
    assert_equal 1, result.submission.updates.count

    baseline = result.submission.updates.first.parsed_patch
    assert_equal 1,     baseline.size, 'first-import baseline must be a single op'
    assert_equal 'add', baseline.first['op']
    assert_equal '',    baseline.first['path']

    # Materialise via PURE REPLAY (cache cleared) — must include
    # the volatile fields the baseline carries.
    result.submission.cached_materialised_record.purge
    result.submission.update_columns(cached_at_update_id: nil)
    replayed = result.submission.reload.materialised_record

    assert_equal 'v3',                                replayed['schema_version']
    assert_equal({'source_format' => 'dway_bp_xml'},  replayed['provenance'])
    assert replayed.key?('project'),     'project must be in the materialised replay'
    assert replayed.key?('submission'),  'submission must be in the materialised replay'
  end

  test 'creates Submission + Project + baseline SubmissionUpdate on first run' do
    result = build.call

    assert_equal :created, result.outcome
    submission = result.submission
    assert_equal 'PSUB000604', submission.source_id
    assert_equal 'bioproject', submission.db
    assert_equal 'migration-test', submission.user.uid
    assert_equal 1, submission.canonical_version
    assert_match(%r{\Abp_v3/}, submission.converter_version)
    refute_nil submission.migration_run_id

    project = submission.project
    assert_equal 'PRJDB502', project.accession
    assert_equal 'primary',  project.project_type

    assert_equal 1, submission.updates.count
  end

  test 'accession kwarg threads through Importer → Converter → Project (DB-column-wins end-to-end)' do
    # End-to-end seam test for the headline recovery contract:
    # data_migration.rake passes `accession: row.accession` from the
    # staging Submission Data; Importer forwards into Converter's
    # project_row; Converter precedence picks DB over XML; Project.accession
    # gets the DB value. Without this test, a refactor that drops
    # `accession: @accession` from the Converter call (importer.rb line
    # threading) would silently regress without any Converter unit test
    # noticing — the existing :created test uses XML=DB so both paths
    # produce the same string.
    result = build(accession: 'PRJDB7777777').call

    assert_equal :created, result.outcome
    assert_equal 'PRJDB7777777', result.submission.project.accession,
                 'Importer must thread accession: kwarg through to Project.accession'
    # Note: materialised_record does NOT carry project.accession because
    # `/**/accession` is registered as volatile (Canonicalizer strips it
    # from the patch chain on diff). The typed Project.accession column
    # IS the authoritative read path for accession — verified above.
  end

  test 're-run with identical XML is :skipped and does not touch Submission / Project rows' do
    first       = build.call.submission
    first_run   = first.migration_run_id
    first_seen  = first.updated_at
    first_title = first.project.title

    travel 1.second
    first.project.update!(title: 'Curator-edited title')

    second = build(migration_run_id: SecureRandom.uuid).call
    assert_equal :skipped, second.outcome

    submission = second.submission
    assert_equal first_run, submission.reload.migration_run_id, 'migration_run_id must NOT be restamped on :skipped'
    assert_equal first_seen.to_i, submission.updated_at.to_i,    'updated_at must NOT be bumped on :skipped'
    assert_equal 'Curator-edited title', submission.project.reload.title,
                 'Project columns must NOT be clobbered by an idempotent re-run'
    refute_equal first_title, 'Curator-edited title' # sanity: the precondition flipped
    assert_equal 1, submission.updates.count
  end

  test 'on a real :updated run migration_run_id IS restamped' do
    first = build.call.submission

    second_run = SecureRandom.uuid
    edited_xml = File.read(XML_FIXTURE).sub('Chromosome Mycobacterium avium sequencing',
                                            'Chromosome Mycobacterium avium sequencing v2')

    result = BioProject::Importer.new(
      psub_id:          'PSUB000604',
      xml:              edited_xml,
      user_uid:         'migration-test',
      project_type:     'primary',
      accession:        'PRJDB502',
      migration_run_id: second_run
    ).call

    assert_equal :updated,    result.outcome
    assert_equal second_run,  result.submission.reload.migration_run_id
    refute_equal first.migration_run_id, second_run # sanity
  end

  test 're-run dedup survives the UTF-8 vs bytea encoding gap on non-ASCII payloads' do
    # PG bytea round-trips as ASCII-8BIT; Oj.dump emits UTF-8. Ruby `==`
    # treats them as unequal whenever any byte is >= 0x80, which would
    # otherwise re-append an identical-bytes baseline patch on every
    # re-run for any record with multi-byte characters.
    xml = File.read(XML_FIXTURE).sub('<Title>', '<Title>café ')

    importer = BioProject::Importer.new(
      psub_id:          'PSUB-encoding',
      xml:              xml,
      user_uid:         'migration-test',
      project_type:     'primary',
      accession:        'PRJDB502',
      migration_run_id: SecureRandom.uuid
    )

    importer.call
    second = importer.call

    assert_equal :skipped, second.outcome
    assert_equal 1,        second.submission.updates.count
  end

  test 'rejects cross-user re-attribution' do
    build.call

    assert_raises BioProject::Importer::CrossUserError do
      build(user_uid: 'someone-else').call
    end
  end

  test 'finds existing User by uid instead of creating a duplicate' do
    user = User.create!(uid: 'existing-curator')
    result = build(user_uid: 'existing-curator').call

    assert_equal user, result.submission.user
  end

  test 'maps legacy status_id 700 to :public' do
    result = build(status: 700).call

    assert_equal 'public', result.submission.project.status
  end

  test 'maps unknown status_id to :curating as safe fallback' do
    result = build(status: 99_999).call

    assert_equal 'curating', result.submission.project.status
  end

  test 'returns :no_accession (no raise) when XML lacks ArchiveID/@accession' do
    bare_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <PackageSet>
        <Package><Project><Project><ProjectID><ArchiveID /></ProjectID>
        <ProjectDescr><Title>placeholder</Title></ProjectDescr>
        </Project></Project></Package>
      </PackageSet>
    XML

    result = BioProject::Importer.new(
      psub_id:          'PSUB000009',
      xml:              bare_xml,
      user_uid:         'migration-test',
      project_type:     'primary',
      migration_run_id: SecureRandom.uuid
    ).call

    assert_equal :no_accession, result.outcome
    assert_nil   result.submission
    assert_nil   Submission.find_by(source_id: 'PSUB000009')
  end
end
