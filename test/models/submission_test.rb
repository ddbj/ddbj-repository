require 'test_helper'

class SubmissionTest < ActiveSupport::TestCase
  # --- ddbj-canon/v1 chains ---------------------------------------------
  # v1 stored root snapshots in raw converter order; v2 diffs index into
  # canonical order. Appending a positional patch to a v1 chain would name
  # the wrong element of a keyed array — silently.

  def seed_v1_chain(submission, record)
    SubmissionUpdate.create_with_patch!(
      submission:, patch_json: Oj.dump([{'op' => 'add', 'path' => '', 'value' => record}], mode: :strict),
      db: submission.db, status: :applied, actor: 'legacy', source: :migration,
      patch_canonical_version: 1
    )
    submission.update_columns(canonical_version: 1)
  end

  test 'a v1 chain is healed rather than extended with a positional patch' do
    submission = submissions(:biosample)
    # Not in key order — this is what makes the mis-indexing observable.
    seed_v1_chain(submission, {'schema_version' => 'v3',
                               'samples' => [{'alias' => 'zz'}, {'alias' => 'aa'}]})

    wanted = submission.materialised_record.deep_dup
    wanted['samples'].find { it['alias'] == 'aa' }['accession'] = 'SAMD1'

    submission.append_update!(wanted, actor: 'admin:tanaka')

    by_alias = submission.reload.materialised_record.fetch('samples').index_by { it['alias'] }

    assert_equal 'SAMD1', by_alias.fetch('aa')['accession'], 'the edit must land on the sample it named'
    assert_nil            by_alias.fetch('zz')['accession']
  end

  test 'healing stamps the chain so the next edit can diff normally' do
    submission = submissions(:biosample)
    seed_v1_chain(submission, {'schema_version' => 'v3', 'samples' => [{'alias' => 'zz'}, {'alias' => 'aa'}]})

    submission.append_update!(
      submission.materialised_record.deep_dup.tap { it['samples'].first['title'] = 'T' },
      actor: 'admin:tanaka'
    )

    assert_equal DDBJRecord::Canonicalizer::NUMBER, submission.reload.canonical_version

    # Now an ordinary minimal diff, not another whole-record snapshot.
    update = submission.append_update!(
      submission.materialised_record.deep_dup.tap { it['samples'].last['title'] = 'U' },
      actor: 'admin:tanaka'
    )

    assert_equal 1,  update.parsed_patch.size
    refute_equal '', update.parsed_patch.first.fetch('path')
  end

  # --- replay past damage ------------------------------------------------
  # A root snapshot replaces the whole document, so nothing before it can
  # affect the result. Replay therefore starts there — which is what makes
  # the importers' "self-heal forward" actually heal: a poisoned patch used
  # to stop replay dead, and the snapshot written afterwards was never
  # reached, leaving a record only the cache could produce.

  def poison!(submission)
    SubmissionUpdate.create_with_patch!(
      submission:, patch_json: 'not-json', db: submission.db, status: :applied,
      actor: 'test', source: :manual, patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
    )
  end

  test 'a poisoned patch stops replay while it is the head of the chain' do
    submission = submissions(:bioproject)
    submission.append_update!({'projects' => [{'title' => 'one'}]}, actor: 'test')
    poison!(submission)

    assert_raises(Submission::MaterialisationFailed) { submission.materialise_at }
  end

  test 'a later root snapshot restores replay' do
    submission = submissions(:bioproject)
    submission.append_update!({'projects' => [{'title' => 'one'}]}, actor: 'test')
    poison!(submission)

    # What the importer writes when safe_prior_materialised has swallowed
    # the failure: a whole-document snapshot.
    SubmissionUpdate.create_with_patch!(
      submission:,
      patch_json: Oj.dump([{'op' => 'add', 'path' => '', 'value' => {'projects' => [{'title' => 'two'}]}}], mode: :strict),
      db: 'bioproject', status: :applied, actor: 'migration:test', source: :migration,
      patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
    )

    assert_equal({'projects' => [{'title' => 'two'}]}, submission.materialise_at)
  end

  test 'the snapshot does not claim to repair the past' do
    submission = submissions(:bioproject)
    submission.append_update!({'projects' => [{'title' => 'one'}]}, actor: 'test')
    poisoned = poison!(submission)

    SubmissionUpdate.create_with_patch!(
      submission:,
      patch_json: Oj.dump([{'op' => 'add', 'path' => '', 'value' => {'projects' => [{'title' => 'two'}]}}], mode: :strict),
      db: 'bioproject', status: :applied, actor: 'migration:test', source: :migration,
      patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
    )

    # Head replays again...
    assert_equal({'projects' => [{'title' => 'two'}]}, submission.materialise_at)

    # ...but `?as_of=` behind the damage still fails. That state genuinely
    # cannot be reconstructed, and pretending otherwise would be worse.
    assert_raises(Submission::MaterialisationFailed) { submission.materialise_at(update_id: poisoned.id) }
  end

  test 'a whole-document replace also resets the replay start' do
    submission = submissions(:bioproject)
    poison!(submission)

    SubmissionUpdate.create_with_patch!(
      submission:,
      patch_json: Oj.dump([{'op' => 'replace', 'path' => '', 'value' => {'projects' => [{'title' => 'x'}]}}], mode: :strict),
      db: 'bioproject', status: :applied, actor: 'test', source: :manual,
      patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
    )

    assert_equal({'projects' => [{'title' => 'x'}]}, submission.materialise_at)
  end

  # A patch we cannot read must not be trusted to claim it resets anything.
  test 'an unreadable patch is never marked as a snapshot' do
    submission = submissions(:bioproject)

    refute poison!(submission).root_snapshot?
  end

  test 'an ordinary minimal patch is not a snapshot' do
    submission = submissions(:bioproject)
    submission.append_update!({'projects' => [{'title' => 'one'}]}, actor: 'test')
    update = submission.append_update!({'projects' => [{'title' => 'two'}]}, actor: 'test')

    refute update.root_snapshot?
  end

  # Inputs canonicalisation rejects have no canonical form; the fallback
  # must still store something rather than re-raising the error it caught.
  test 'a record canonicalisation rejects still falls back to a snapshot' do
    submission = submissions(:bioproject)
    submission.append_update!({'schema_version' => 'v3', 'projects' => [{'title' => 'seed'}]}, actor: 'test')

    # A float where the registry allows none — canonicalize raises, so the
    # diff path and the canonical snapshot path both fail.
    weird = submission.materialised_record.deep_dup.tap { it['projects'][0]['weight'] = 1.5 }

    assert_nothing_raised { submission.append_update!(weird, actor: 'admin:tanaka') }
    assert_equal 1.5, submission.reload.materialised_record.dig('projects', 0, 'weight')
  end

  test '#materialised_record returns nil before any update is appended' do
    submission = submissions(:bioproject)

    assert_nil submission.materialised_record
  end

  test '#materialised_record replays a single baseline patch into the full v3 hash' do
    submission = submissions(:bioproject)
    record     = {
      'schema_version' => 'v3',
      'projects'        => [{'accession' => 'PRJDB502', 'title' => 'sample'}]
    }
    baseline = [{'op' => 'add', 'path' => '', 'value' => record}]

    SubmissionUpdate.create_with_patch!(
      submission:              submission,
      patch_json:              Oj.dump(baseline, mode: :strict),
      db:                      'bioproject',
      status:                  'applied',
      actor:                   'migration',
      source:                  'migration',
      patch_canonical_version: DDBJRecord::Canonicalizer::VERSION
    )

    assert_equal record, submission.materialised_record
  end

  test '#materialised_record replays a chain of patches in id order' do
    submission = submissions(:bioproject)

    baseline = [{'op' => 'add', 'path' => '', 'value' => {'projects' => [{'title' => 'first'}]}}]
    edit     = [{'op' => 'replace', 'path' => '/projects/0/title', 'value' => 'second'}]

    [baseline, edit].each do |patch|
      SubmissionUpdate.create_with_patch!(
        submission:              submission,
        patch_json:              Oj.dump(patch, mode: :strict),
        db:                      'bioproject',
        status:                  'applied',
        actor:                   'migration',
        source:                  'migration',
        patch_canonical_version: DDBJRecord::Canonicalizer::VERSION
      )
    end

    assert_equal 'second', submission.materialised_record.dig('projects', 0, 'title')
  end

  test '#materialised_record raises MaterialisationFailed carrying the offending update_id' do
    submission = submissions(:bioproject)
    bad_update = SubmissionUpdate.create_with_patch!(
      submission:              submission,
      patch_json:              'not-json-at-all',
      db:                      'bioproject',
      status:                  'applied',
      actor:                   'test',
      source:                  'manual',
      patch_canonical_version: 1
    )

    error = assert_raises(Submission::MaterialisationFailed) do
      submission.materialised_record
    end

    assert_equal bad_update.id, error.update_id
    assert_kind_of Oj::ParseError, error.original
  end

  # A cache is derived data. Its object can be gone while the chain that
  # produced it is intact — a store restored from an older backup, an
  # environment pointed at a new bucket — and replaying is then the right
  # answer rather than the expensive one.
  #
  # It used to raise out of `materialised_record` unwrapped, past the
  # rescue in BioProject::Importer that exists to decide exactly this,
  # and stop an import whose purpose was to put the missing record back.
  test '#materialised_record replays the chain when the cached object has gone' do
    submission = submissions(:bioproject)

    submission.append_update!({'projects' => [{'title' => 'from the chain'}]}, actor: 'test')

    assert_equal 'from the chain', submission.materialised_record.dig('projects', 0, 'title')
    assert submission.cached_at_update_id.present?, 'the read primed the cache'

    # The row still says there is a cache; the object behind it is gone.
    was = submission.cached_materialised_record.blob.key

    ActiveStorage::Blob.service.delete(was)

    assert_equal 'from the chain', submission.reload.materialised_record.dig('projects', 0, 'title')

    # Replayed AND re-primed. Asserting only the value would pass whether
    # the cache was read or rebuilt, which is the whole of what changed.
    assert_not_equal was, submission.reload.cached_materialised_record.blob.key
  end

  # The other reader of the same object. It is what the admin screen
  # calls, so answering with the exception made the one screen a curator
  # would open to look at the record the only reader that could not.
  test '#cached_materialised_bytes answers nil when the cached object has gone' do
    submission = submissions(:bioproject)

    submission.append_update!({'projects' => [{'title' => 'v1'}]}, actor: 'test')
    submission.materialised_record

    ActiveStorage::Blob.service.delete(submission.cached_materialised_record.blob.key)

    assert_nil submission.reload.cached_materialised_bytes
  end

  # And a store that is not answering still goes up: reading it as a
  # miss would replay every submission in a sweep, and reading it as
  # empty would discard the chain.
  test '#materialised_record does not swallow a store that is not answering' do
    submission = submissions(:bioproject)

    submission.append_update!({'projects' => [{'title' => 'v1'}]}, actor: 'test')
    submission.materialised_record

    dead = Aws::S3::Errors::ServiceUnavailable.new(nil, 'the store is not answering')

    ActiveStorage::Blob.service.stub(:download, ->(*) { raise dead }) do
      assert_raises(Aws::S3::Errors::ServiceUnavailable) { submission.reload.materialised_record }
    end
  end

  test '#materialise_at(update_id:) replays only up to the given update' do
    submission = submissions(:bioproject)
    baseline   = submission.append_update!({'projects' => [{'title' => 'v1'}]}, actor: 'test')
    edit       = submission.append_update!({'projects' => [{'title' => 'v2'}]}, actor: 'test')

    assert_equal 'v1', submission.materialise_at(update_id: baseline.id).dig('projects', 0, 'title')
    assert_equal 'v2', submission.materialise_at(update_id: edit.id).dig('projects', 0, 'title')
    assert_equal 'v2', submission.materialise_at.dig('projects', 0, 'title')
  end

  test '#append_update! computes diff, appends, no-op when nothing changed' do
    submission = submissions(:bioproject)
    submission.append_update!({'projects' => [{'title' => 'hello'}]}, actor: 'curator')
    assert_equal 1, submission.updates.count

    again = submission.append_update!({'projects' => [{'title' => 'hello'}]}, actor: 'curator')
    assert_nil again, 'identical record should produce empty diff and skip insert'
    assert_equal 1, submission.updates.count

    submission.append_update!({'projects' => [{'title' => 'world'}]}, actor: 'curator')
    assert_equal 2, submission.updates.count
    assert_equal 'world', submission.materialised_record.dig('projects', 0, 'title')
  end

  test '#append_update! replaces an edited bag element whole (e.g. submitter organizations)' do
    submission = submissions(:bioproject)

    submission.append_update!(
      {
        'submission' => {
          'submitters' => [{
            'first_name'    => 'Hanako',
            'organizations' => [{'name' => 'NIG', 'role' => 'owner'}]
          }]
        }
      },
      actor: 'seed'
    )

    # Edit: add `url` to the existing organization. A patch into the
    # element (`add /submission/submitters/0/organizations/0/url`) would
    # descend into the `/submission/submitters/*/organizations` bag, which
    # the patch verifier rejects (§3.1), so the element is replaced whole.
    submission.append_update!(
      {
        'submission' => {
          'submitters' => [{
            'first_name'    => 'Hanako',
            'organizations' => [{'name' => 'NIG', 'role' => 'owner', 'url' => 'https://nig.ac.jp/'}]
          }]
        }
      },
      actor: 'curator'
    )

    patch = submission.updates.order(:id).last.parsed_patch

    assert_equal [%w[remove /submission/submitters/0/organizations/0], %w[add /submission/submitters/0/organizations/0]],
                 patch.map { [it['op'], it['path']] }

    assert_equal 'https://nig.ac.jp/',
                 submission.materialised_record.dig('submission', 'submitters', 0, 'organizations', 0, 'url')
  end

  test 'round-trip: apply(empty, diff(empty, R)) == R for 50 random records' do
    submission = Submission.create!(db: 'bioproject', user: users(:alice), source_id: "rt-#{SecureRandom.hex(4)}")
    50.times do |i|
      record = {
        'projects' => [{
          'accession'   => "PRJDB#{1000 + i}",
          'title'       => "title-#{SecureRandom.hex(3)}",
          'description' => "desc\nline2\nline3" * (i % 3 + 1)
        }]
      }

      submission.updates.destroy_all
      submission.append_update!(record, actor: 'rt')

      assert_equal DDBJRecord::Canonicalizer.sha256(record, for_diff: true),
                   DDBJRecord::Canonicalizer.sha256(submission.materialised_record, for_diff: true),
                   "round-trip failed for iteration #{i}"
    end
  end

  test 'append_update! serialises concurrent writers via row-level lock' do
    skip 'sqlite test env lacks row locking' if ActiveRecord::Base.connection.adapter_name.match?(/sqlite/i)

    submission = Submission.create!(db: 'bioproject', user: users(:alice), source_id: "race-#{SecureRandom.hex(4)}")
    submission.append_update!({'projects' => [{'title' => 'v0'}]}, actor: 'seed')

    threads = 4.times.map {|i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          fresh = Submission.find(submission.id)
          fresh.append_update!({'projects' => [{'title' => "v#{i + 1}"}]}, actor: "writer-#{i}")
        end
      end
    }
    threads.each(&:join)

    # All 4 appends must have landed; replay must succeed (no diverged chain).
    assert_equal 5, submission.updates.reload.count
    assert_includes %w[v0 v1 v2 v3 v4], submission.materialised_record.dig('projects', 0, 'title')
  end

  test 'write-through cache: first call attaches blob + stamps; second call returns from cache without replay' do
    submission = submissions(:bioproject)
    submission.append_update!({'projects' => [{'title' => 'cached'}]}, actor: 'test')

    assert_nil submission.reload.cached_at_update_id
    assert_not submission.cached_materialised_record.attached?

    first = submission.materialised_record
    assert_equal 'cached', first.dig('projects', 0, 'title')

    submission.reload
    assert submission.cached_materialised_record.attached?, 'cache blob must be attached after write-through'
    assert_equal submission.updates.maximum(:id), submission.cached_at_update_id

    # On the cache hit path, do not invoke the replay engine. Stubbing
    # Canonicalizer.apply to raise asserts the bypass without depending
    # on the patch storage's evolving integrity rules.
    DDBJRecord::Canonicalizer.stub(:apply, ->(*) { raise 'replay must not be called on cache hit' }) do
      assert_equal first, submission.materialised_record,
                   'cache hit must bypass patch replay entirely'
    end
  end

  test 'write-through cache: invalidates when a new update is appended' do
    submission = submissions(:bioproject)
    submission.append_update!({'projects' => [{'title' => 'v1'}]}, actor: 'test')
    submission.materialised_record # warms cache

    assert submission.reload.cached_at_update_id.present?, 'baseline cache warm-up must populate cache'

    submission.append_update!({'projects' => [{'title' => 'v2'}]}, actor: 'test')

    # SubmissionUpdate#after_create must have nil-cleared the cache stamp.
    assert_nil submission.reload.cached_at_update_id, 'append must invalidate cache'

    # Next read recomputes and re-stamps at the new latest.
    assert_equal 'v2', submission.materialised_record.dig('projects', 0, 'title')
    assert_equal submission.updates.reload.maximum(:id), submission.reload.cached_at_update_id
  end

  test 'write-through cache: invalidates when a SubmissionUpdate is destroyed' do
    submission = submissions(:bioproject)
    submission.append_update!({'projects' => [{'title' => 'v1'}]}, actor: 'test')
    second = submission.append_update!({'projects' => [{'title' => 'v2'}]}, actor: 'test')
    submission.materialised_record # warms cache at v2
    assert submission.reload.cached_at_update_id.present?

    second.destroy!

    assert_nil submission.reload.cached_at_update_id,
               'after_destroy must invalidate cache when any update row is destroyed'
  end

  test 'materialise_at(update_id:) historical snapshots never consult the cache' do
    submission = submissions(:bioproject)
    first  = submission.append_update!({'projects' => [{'title' => 'v1'}]}, actor: 'test')
    second = submission.append_update!({'projects' => [{'title' => 'v2'}]}, actor: 'test')

    submission.materialised_record # populates cache at second.id

    # Cache is for "latest"; historical snapshots must replay so the
    # cache cannot serve the wrong-version data to a ?as_of query.
    assert_equal 'v1', submission.materialise_at(update_id: first.id).dig('projects', 0, 'title')
    assert_equal 'v2', submission.materialise_at(update_id: second.id).dig('projects', 0, 'title')
  end

  # Only a MASS submission has a directory; one posted to the API keeps
  # everything in object storage and never grows one. after_destroy
  # removes the directory unconditionally, which is safe because
  # `Pathname#rmtree` treats a missing path as nothing to do — pinned
  # here because the whole of a bulk cleanup rides on it. A stricter
  # removal would roll the destroy back, and every ST.26 submission is
  # API-sourced.
  test 'a submission with no directory on disk can still be destroyed' do
    submission = Submission.create!(db: 'st26', user: users(:alice), source_id: "no-dir-#{SecureRandom.hex(4)}")

    assert_not submission.dir.exist?

    assert_difference 'Submission.count', -1 do
      submission.destroy!
    end
  end

  test 'destroying a submission takes its directory with it' do
    submission = Submission.create!(db: 'st26', user: users(:alice), source_id: "with-dir-#{SecureRandom.hex(4)}")

    submission.dir.mkpath
    submission.dir.join('flatfile').write('LOCUS')

    submission.destroy!

    assert_not submission.dir.exist?
  end

  test 'materialise_at p99 < 500ms over a 30-patch chain' do
    submission = Submission.create!(db: 'bioproject', user: users(:alice), source_id: "bench-#{SecureRandom.hex(4)}")
    30.times {|i| submission.append_update!({'projects' => [{'title' => "v#{i}"}]}, actor: 'bench') }

    timings = Array.new(20) do
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      submission.materialised_record
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000
    end

    p99 = timings.sort[(timings.size * 0.99).ceil - 1]
    assert_operator p99, :<, 500, "30-patch p99 was #{p99.round(2)}ms"
  end

  # --- the flatfile against the statuses --------------------------------
  # What the file left out is recorded with it, because the question the
  # Entries tab asks — does this file still match these statuses — has no
  # answer in a timestamp. The two writes below are why: both move
  # `entries.updated_at` and neither changes a byte of the file.

  def st26_with_entries(omits: nil)
    submission = Submission.create!(db: 'st26', user: users(:alice), source_id: "ff-#{SecureRandom.hex(4)}")

    submission.entries.create!(entry_id: 'A|1', accession: 'X00001', version: 1, locus_date: Date.new(2026, 1, 1))
    submission.entries.create!(entry_id: 'A|2', accession: 'X00002', version: 1, locus_date: Date.new(2026, 1, 1))

    submission.ddbj_record.attach(io: StringIO.new('{}'), filename: 'x.json', content_type: 'application/json')
    submission.update!(flatfile_omits: omits) unless omits.nil?
    attach_flatfile submission

    submission
  end

  def attach_flatfile(submission)
    submission.flatfile_na.attach(io: StringIO.new('LOCUS'), filename: 'x-na.flat', content_type: 'text/plain')
  end

  test 'a file that left nothing out and has nothing retracted is not behind' do
    submission = st26_with_entries(omits: [])

    assert_empty submission.flatfile_drift.still_carried
    assert_empty submission.flatfile_drift.still_omitted
    assert_not submission.flatfile_behind_statuses?
  end

  test 'a retraction the file has not dropped yet is named' do
    submission = st26_with_entries(omits: [])
    submission.entries.first.update!(status: :canceled)

    assert_equal ['A|1'], submission.flatfile_drift.still_carried
    assert submission.flatfile_behind_statuses?
  end

  # The direction a timestamp cannot see: the entry is back, and the file
  # is still without it.
  test 'an entry put back that the file still leaves out is named' do
    submission = st26_with_entries(omits: ['A|1'])

    assert_equal ['A|1'], submission.flatfile_drift.still_omitted
    assert submission.flatfile_behind_statuses?
  end

  test 'a file that left out exactly what is retracted is not behind' do
    submission = st26_with_entries(omits: ['A|1'])
    submission.entries.first.update!(status: :canceled)

    assert_not submission.flatfile_drift.any?
    assert_not submission.flatfile_behind_statuses?
  end

  # Publishing is the ordinary end of an ST.26 submission's life and
  # changes no byte of the file. Read from a timestamp it lit the panel on
  # every published submission, and the press could not clear it: the
  # regeneration writes nothing, so the timestamp stays where it was.
  test 'publishing an entry does not put the file behind' do
    submission = st26_with_entries(omits: [])
    submission.entries.each { it.update!(status: :public) }

    assert_not submission.flatfile_behind_statuses?
  end

  # The 2026-08-10 backfill stamped 9,813,674 entries over 17,999
  # submissions to restore `locus_date`, and said itself that the
  # flatfiles were untouched.
  test 'a column-only write across the archive does not put the file behind' do
    submission = st26_with_entries(omits: [])
    submission.entries.update_all(locus_date: Date.new(2020, 1, 1), updated_at: Time.current)

    assert_not submission.flatfile_behind_statuses?
  end

  # Retracting every entry leaves no flatfile at all — `generate_outputs`
  # yields nil for an empty one and `write_outputs!` detaches it. That
  # state reflects the statuses exactly, and read from the file's age it
  # looked permanently behind.
  test 'a submission whose entries are all retracted has nothing to fix' do
    submission = st26_with_entries(omits: ['A|1', 'A|2'])
    submission.entries.each { it.update!(status: :canceled) }
    submission.flatfile_na.purge

    assert_not submission.flatfile_behind_statuses?
  end

  # Every file in the archive predates the record of what it left out.
  # Until one is regenerated the older reading stands: a retraction newer
  # than the file says it may still be carried, and nothing says anything
  # about an entry put back.
  test 'a file written before this was recorded falls back to its own age' do
    submission = st26_with_entries

    assert_nil submission.flatfile_drift
    assert_not submission.flatfile_behind_statuses?

    submission.entries.first.update!(status: :canceled)

    assert submission.flatfile_behind_statuses?
  end

  # --- curation rows ------------------------------------------------------

  test 'a DRA submission is curated as its one row, like a BioProject' do
    submission = submissions(:dra)

    assert_equal [dra_submissions(:dra)], submission.curation_rows.to_a
    assert_equal ['DRA000001', 1],        submission.accession_summary
    assert_equal 'DRA submission',        submission.curation_row_noun
  end

  test 'every database has a label people read' do
    assert_equal Submission.dbs.keys.sort, Submission::DB_LABELS.keys.sort
  end

  # A read replays, then stamps. An edit landing between the two has
  # already cleared the stamp, which is then no guard: what was replayed
  # before the edit must not be kept as current after it.
  test 'a cache replayed before an edit is not stamped as current after it' do
    submission = submissions(:biosample)
    patch      = ->(ops) { SubmissionUpdate.create_with_patch!(submission:, patch_json: ops.to_json, db: 'biosample', status: :applied, actor: 'test', source: :manual) }

    first = patch.([{op: 'add', path: '', value: {'schema_version' => 'v3', 'samples' => [{'alias' => 's', 'title' => 'Before'}]}}])
    stale = Oj.dump(submission.materialise_at(update_id: first.id), mode: :strict)

    patch.([{op: 'replace', path: '/samples/0/title', value: 'After'}])

    submission.reload.prime_cache!(bytes: stale, update_id: first.id)

    assert_nil submission.reload.cached_at_update_id
  end

  # --- republication (DB-2096) -----------------------------------------

  def record_with(samples, submission: {})
    {'schema_version' => 'v3', 'submission' => submission, 'samples' => samples}
  end

  # A change to what is public about a sample publishes it again; the
  # samples the change does not touch, and those not yet public, keep
  # their dates.
  test 'an edit republishes the public samples it changes, and only those' do
    submission = submissions(:biosample)
    submission.samples.update_all(status: Lifecycleable::STATUSES.fetch('private'))
    changed    = submission.samples.create!(sample_name: 'changed',   status: :public,  last_published_at: 1.year.ago)
    untouched  = submission.samples.create!(sample_name: 'untouched', status: :public,  last_published_at: 1.year.ago)
    unreleased = submission.samples.create!(sample_name: 'private',   status: :private)

    submission.append_update!(record_with([{'alias' => 'changed', 'title' => 'A'}, {'alias' => 'untouched'}, {'alias' => 'private', 'title' => 'A'}]), actor: 'test')

    before = [changed, untouched].map { it.reload.last_published_at }

    freeze_time do
      submission.append_update!(record_with([{'alias' => 'changed', 'title' => 'B'}, {'alias' => 'untouched'}, {'alias' => 'private', 'title' => 'B'}]), actor: 'test')

      assert_equal Time.current, changed.reload.last_published_at
    end

    assert_equal before[1], untouched.reload.last_published_at
    assert_nil              unreleased.reload.last_published_at
  end

  # A sample publishes its owner besides itself. Who submitted it, and the
  # hold date — over once the samples are public — it does not.
  test 'a change to the owner republishes every public sample, and nothing else in the submission does' do
    submission = submissions(:biosample)
    submission.samples.update_all(status: Lifecycleable::STATUSES.fetch('private'))
    sample     = submission.samples.create!(sample_name: 's', status: :public, last_published_at: 1.year.ago)
    samples    = [{'alias' => 's'}]
    frame      = ->(org, **more) { {'submitters' => [{'first_name' => 'Ada', 'organizations' => [{'name' => org}]}], **more} }

    submission.append_update!(record_with(samples, submission: frame.('DDBJ', 'hold_date' => '2027-01-01')), actor: 'test')
    before = sample.reload.last_published_at

    submission.append_update!(record_with(samples, submission: frame.('DDBJ', 'hold_date' => '2028-01-01', 'comments' => ['x'])), actor: 'test')

    assert_equal before, sample.reload.last_published_at

    freeze_time do
      submission.append_update!(record_with(samples, submission: frame.('NIG')), actor: 'test')

      assert_equal Time.current, sample.reload.last_published_at
    end
  end

  # Reshaping a chain written under an older shape changes how the record
  # is stored, not what it says.
  test 'a write that only reshapes the record republishes nothing' do
    submission = submissions(:biosample)
    submission.samples.update_all(status: Lifecycleable::STATUSES.fetch('private'))
    sample     = submission.samples.create!(sample_name: 's', status: :public, last_published_at: 1.year.ago)

    # Stored as it was before the spec made taxonomy_id a string.
    seed_v1_chain(submission, record_with([{'alias' => 's', 'organism' => {'taxonomy_id' => 9606}}]))
    before = sample.reload.last_published_at

    submission.append_update!(submission.materialised_record, actor: 'ddbj_record:reshape_v3', source: :batch)

    assert_equal before, sample.reload.last_published_at
  end

  test 'an edit to a public project republishes it' do
    submission = submissions(:bioproject)
    project    = submission.project
    project.update_columns(status: Lifecycleable::STATUSES.fetch('public'), last_published_at: 1.year.ago)

    submission.append_update!({'schema_version' => 'v3', 'projects' => [{'title' => 'Before'}]}, actor: 'test')

    freeze_time do
      submission.append_update!({'schema_version' => 'v3', 'projects' => [{'title' => 'After'}]}, actor: 'test')

      assert_equal Time.current, project.reload.last_published_at
    end
  end
end
