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

  # `diff` indexes into the canonical ordering while `apply` runs against
  # whatever is stored, so a baseline in converter order would leave every
  # later patch naming the wrong element of a keyed array.
  test 'the baseline snapshot is stored canonical' do
    submission = build.call.submission

    assert_equal DDBJRecord::Canonicalizer.canonical_tree(submission.materialised_record),
                 submission.materialised_record
  end

  # The importers are what hold the pre-v2 corpus, so the heal has to live
  # here too — a re-import is exactly the operation that would otherwise
  # diff canonical indices against a raw-order baseline and land the ops on
  # the wrong array elements.
  test 'a pre-v2 chain is healed rather than diffed against' do
    submission = build.call.submission

    # Put it back the way v1 left it: raw-order baseline, version 1.
    submission.update_columns(canonical_version: 1, source_checksum: nil)

    result = build.call

    assert_equal :updated, result.outcome

    patch = submission.updates.order(:id).last.parsed_patch

    assert_equal 1,  patch.size, 'a legacy chain must be replaced wholesale, not patched positionally'
    assert_equal '', patch.first.fetch('path')
    assert_equal DDBJRecord::Canonicalizer::NUMBER, submission.reload.canonical_version
  end

  test 'a v2 chain still gets a minimal diff' do
    submission = build.call.submission
    submission.update_columns(source_checksum: nil) # force the diff path

    edited = File.read(XML_FIXTURE).sub('Chromosome Mycobacterium avium sequencing',
                                        'Chromosome Mycobacterium avium sequencing v2')

    BioProject::Importer.new(
      psub_id: 'PSUB000604', xml: edited, user_uid: 'migration-test',
      project_type: 'primary', accession: 'PRJDB502', migration_run_id: SecureRandom.uuid
    ).call

    patch = submission.updates.order(:id).last.parsed_patch

    refute_equal '', patch.first.fetch('path'), 'a healthy chain must not be replaced wholesale'
  end

  # `safe_prior_materialised` swallows a replay failure so the importer can
  # "self-heal forward". It only actually heals because the snapshot it
  # then writes resets where replay starts — otherwise the record stayed
  # readable through the cache alone, with the chain unable to reproduce it.
  test 'a re-import repairs a chain a poisoned patch had stopped' do
    submission = build.call.submission

    SubmissionUpdate.create_with_patch!(
      submission:, patch_json: 'not-json', db: 'bioproject', status: :applied,
      actor: 'test', source: :manual, patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
    )
    submission.update_columns(cached_at_update_id: nil, source_checksum: nil)

    assert_raises(Submission::MaterialisationFailed) { submission.materialise_at }

    assert_equal :updated, build.call.outcome

    # Replay works again, and agrees with what the importer cached.
    assert_equal Oj.load(submission.reload.cached_materialised_bytes, mode: :strict),
                 submission.materialise_at
  end

  # The self-heal above is right for a poisoned patch — a fact about this
  # submission. It is exactly wrong for an unreachable object store,
  # which makes EVERY chain read as empty: the importer would then write
  # a root snapshot built from D-way over a chain that was carrying
  # curator edits, and report it as a successful update.
  test 'an unreachable object store is not read as an empty history' do
    submission = build.call.submission
    submission.update_columns(cached_at_update_id: nil, source_checksum: nil)

    refused = Seahorse::Client::NetworkingError.new(SocketError.new('Connection refused'))

    # The blob read is where the store is actually touched.
    error = Oj.stub(:load, ->(*, **) { raise refused }) {
      assert_raises(Submission::MaterialisationFailed) { build.call }
    }

    assert StorageFailure === error, 'the sweep recognises it by the cause it carries'
    assert_equal 1, submission.reload.updates.count, 'nothing may be written over a history we cannot read'
  end

  # An unchanged source is not on its own a reason to skip: the chain's
  # canonical form depends on the canonicaliser too. Without this, the
  # re-import that a canon version bump REQUIRES sweeps the whole corpus,
  # reports every record :skipped, and changes nothing — and the corpus
  # only carries checksums at all once one import has run, so the trap
  # springs on the second bump, not the first.
  test 'a canon version bump re-imports a source that did not change' do
    submission = build.call.submission

    assert_not_nil submission.reload.source_checksum
    assert_equal :skipped, build.call.outcome, 'unchanged source, current canon'

    submission.update_columns(canonical_version: DDBJRecord::Canonicalizer::NUMBER - 1)

    assert_equal :updated, build.call.outcome, 'unchanged source, stale canon'
    assert_equal DDBJRecord::Canonicalizer::NUMBER, submission.reload.canonical_version
  end

  # The fast path now asks "did the source change", which is a property of
  # the converter output alone — no canonicalisation, no chain replay.
  test 'the source checksum is recorded and short-circuits an unchanged re-run' do
    submission = build.call.submission

    assert_not_nil submission.reload.source_checksum

    assert_no_difference 'submission.updates.count' do
      assert_equal :skipped, build.call.outcome
    end
  end

  # A curator edit between imports must survive an unchanged re-run: the
  # question is "did D-way change", not "does the chain still match".
  test 'a curator edit survives an unchanged re-import' do
    submission = build.call.submission
    submission.append_update!(
      submission.materialised_record.deep_dup.tap { it['project']['title'] = 'Curator title' },
      actor: 'admin:tanaka'
    )

    assert_equal :skipped, build.call.outcome
    assert_equal 'Curator title', submission.reload.materialised_record.dig('project', 'title')
  end

  test 'syncs staging release_date / dist_date / modified_date onto Project and backfills on a byte-identical re-run' do
    # First import with no lifecycle dates yet.
    project = build.call.submission.project
    assert_nil project.release_date
    assert_nil project.dist_date
    assert_nil project.modified_date

    # Re-run with the SAME XML but dates now populated in D-way. The XML
    # is byte-identical so the importer takes the :skipped path — but
    # these D-way facts sit outside the diffed chain (release_date /
    # dist_date feed the exchange XML, modified_date is the livelist's
    # Updated) and must still backfill.
    result = build(release_date: '2020-03-10', dist_date: '2021-04-05', modified_date: '2022-05-06').call

    assert_equal :skipped, result.outcome
    project.reload
    assert_equal Date.new(2020, 3, 10), project.release_date
    assert_equal Date.new(2021, 4, 5),  project.dist_date
    assert_equal Date.new(2022, 5, 6),  project.modified_date
  end

  # DistributionNotifier filters on projects.hold_date, so the record's
  # submission.hold_date has to reach the column — including on the
  # fast-skip path, which is how rows imported before the projection
  # existed get backfilled.
  test 'projects the record hold_date onto Project, on both the change and skip paths' do
    result = build.call
    assert_equal :created, result.outcome

    submission = result.submission
    expected   = Date.iso8601(submission.materialised_record.fetch('submission').fetch('hold_date'))

    assert_equal expected, submission.project.hold_date

    submission.project.update_column(:hold_date, nil) # simulate a pre-projection row

    assert_equal :skipped, build.call.outcome
    assert_equal expected, submission.project.reload.hold_date
  end

  test 'creates Submission + Project + baseline SubmissionUpdate on first run' do
    result = build.call

    assert_equal :created, result.outcome
    submission = result.submission
    assert_equal 'PSUB000604', submission.source_id
    assert_equal 'bioproject', submission.db
    assert_equal 'migration-test', submission.user.uid
    assert_equal DDBJRecord::Canonicalizer::NUMBER, submission.canonical_version
    assert_match(%r{\Abp_v3/}, submission.converter_version)
    refute_nil submission.migration_run_id

    project = submission.project
    assert_equal 'PRJDB502', project.accession
    assert_equal 'primary',  project.project_type

    assert_equal 1, submission.updates.count
  end

  test 'mints a synthetic applied request wrapping the submission, idempotent across re-runs' do
    submission = build.call.submission
    request    = submission.request

    assert_not_nil request, 'migration submission must carry a synthetic request'
    assert request.applied?
    assert request.migration_origin?
    assert_equal submission.user, request.user
    assert_equal submission.db,   request.db
    assert_not request.ddbj_record.attached?, 'synthetic request carries no upload'
    assert request.valid?, 'the ddbj_record attachment rule is waived for migration-origin requests'

    # A re-run reuses the existing request rather than minting a duplicate.
    build(migration_run_id: SecureRandom.uuid).call
    assert_equal 1, SubmissionRequest.where(submission_id: submission.id).count
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
    first     = build.call.submission
    first_run = first.migration_run_id

    # From the database, not from `first`. The import writes the row again
    # after this object last read it — the materialised-record cache — so
    # the attribute in memory is a few milliseconds behind what is stored,
    # and a baseline taken from it is comparing two different instants.
    first_seen  = first.reload.updated_at
    first_title = first.project.title

    travel 1.second
    first.project.update!(title: 'Curator-edited title')

    second = build(migration_run_id: SecureRandom.uuid).call
    assert_equal :skipped, second.outcome

    submission = second.submission
    assert_equal first_run, submission.reload.migration_run_id, 'migration_run_id must NOT be restamped on :skipped'
    assert_equal first_seen, submission.updated_at, 'updated_at must NOT be bumped on :skipped'
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
