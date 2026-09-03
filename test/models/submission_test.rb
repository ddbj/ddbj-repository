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
    submission.append_update!({'project' => {'title' => 'one'}}, actor: 'test')
    poison!(submission)

    assert_raises(Submission::MaterialisationFailed) { submission.materialise_at }
  end

  test 'a later root snapshot restores replay' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'one'}}, actor: 'test')
    poison!(submission)

    # What the importer writes when safe_prior_materialised has swallowed
    # the failure: a whole-document snapshot.
    SubmissionUpdate.create_with_patch!(
      submission:,
      patch_json: Oj.dump([{'op' => 'add', 'path' => '', 'value' => {'project' => {'title' => 'two'}}}], mode: :strict),
      db: 'bioproject', status: :applied, actor: 'migration:test', source: :migration,
      patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
    )

    assert_equal({'project' => {'title' => 'two'}}, submission.materialise_at)
  end

  test 'the snapshot does not claim to repair the past' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'one'}}, actor: 'test')
    poisoned = poison!(submission)

    SubmissionUpdate.create_with_patch!(
      submission:,
      patch_json: Oj.dump([{'op' => 'add', 'path' => '', 'value' => {'project' => {'title' => 'two'}}}], mode: :strict),
      db: 'bioproject', status: :applied, actor: 'migration:test', source: :migration,
      patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
    )

    # Head replays again...
    assert_equal({'project' => {'title' => 'two'}}, submission.materialise_at)

    # ...but `?as_of=` behind the damage still fails. That state genuinely
    # cannot be reconstructed, and pretending otherwise would be worse.
    assert_raises(Submission::MaterialisationFailed) { submission.materialise_at(update_id: poisoned.id) }
  end

  test 'a whole-document replace also resets the replay start' do
    submission = submissions(:bioproject)
    poison!(submission)

    SubmissionUpdate.create_with_patch!(
      submission:,
      patch_json: Oj.dump([{'op' => 'replace', 'path' => '', 'value' => {'project' => {'title' => 'x'}}}], mode: :strict),
      db: 'bioproject', status: :applied, actor: 'test', source: :manual,
      patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
    )

    assert_equal({'project' => {'title' => 'x'}}, submission.materialise_at)
  end

  # A patch we cannot read must not be trusted to claim it resets anything.
  test 'an unreadable patch is never marked as a snapshot' do
    submission = submissions(:bioproject)

    refute poison!(submission).root_snapshot?
  end

  test 'an ordinary minimal patch is not a snapshot' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'one'}}, actor: 'test')
    update = submission.append_update!({'project' => {'title' => 'two'}}, actor: 'test')

    refute update.root_snapshot?
  end

  # Inputs canonicalisation rejects have no canonical form; the fallback
  # must still store something rather than re-raising the error it caught.
  test 'a record canonicalisation rejects still falls back to a snapshot' do
    submission = submissions(:bioproject)
    submission.append_update!({'schema_version' => 'v3', 'project' => {'title' => 'seed'}}, actor: 'test')

    # A float where the registry allows none — canonicalize raises, so the
    # diff path and the canonical snapshot path both fail.
    weird = submission.materialised_record.deep_dup.tap { it['project']['weight'] = 1.5 }

    assert_nothing_raised { submission.append_update!(weird, actor: 'admin:tanaka') }
    assert_equal 1.5, submission.reload.materialised_record.dig('project', 'weight')
  end

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

    baseline = [{'op' => 'add', 'path' => '', 'value' => {'project' => {'title' => 'first'}}}]
    edit     = [{'op' => 'replace', 'path' => '/project/title', 'value' => 'second'}]

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

    assert_equal 'second', submission.materialised_record.dig('project', 'title')
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

    submission.append_update!({'project' => {'title' => 'from the chain'}}, actor: 'test')

    assert_equal 'from the chain', submission.materialised_record.dig('project', 'title')
    assert submission.cached_at_update_id.present?, 'the read primed the cache'

    # The row still says there is a cache; the object behind it is gone.
    was = submission.cached_materialised_record.blob.key

    ActiveStorage::Blob.service.delete(was)

    assert_equal 'from the chain', submission.reload.materialised_record.dig('project', 'title')

    # Replayed AND re-primed. Asserting only the value would pass whether
    # the cache was read or rebuilt, which is the whole of what changed.
    assert_not_equal was, submission.reload.cached_materialised_record.blob.key
  end

  # The other reader of the same object. It is what the admin screen
  # calls, so answering with the exception made the one screen a curator
  # would open to look at the record the only reader that could not.
  test '#cached_materialised_bytes answers nil when the cached object has gone' do
    submission = submissions(:bioproject)

    submission.append_update!({'project' => {'title' => 'v1'}}, actor: 'test')
    submission.materialised_record

    ActiveStorage::Blob.service.delete(submission.cached_materialised_record.blob.key)

    assert_nil submission.reload.cached_materialised_bytes
  end

  # And a store that is not answering still goes up: reading it as a
  # miss would replay every submission in a sweep, and reading it as
  # empty would discard the chain.
  test '#materialised_record does not swallow a store that is not answering' do
    submission = submissions(:bioproject)

    submission.append_update!({'project' => {'title' => 'v1'}}, actor: 'test')
    submission.materialised_record

    dead = Aws::S3::Errors::ServiceUnavailable.new(nil, 'the store is not answering')

    ActiveStorage::Blob.service.stub(:download, ->(*) { raise dead }) do
      assert_raises(Aws::S3::Errors::ServiceUnavailable) { submission.reload.materialised_record }
    end
  end

  test '#materialise_at(update_id:) replays only up to the given update' do
    submission = submissions(:bioproject)
    baseline   = submission.append_update!({'project' => {'title' => 'v1'}}, actor: 'test')
    edit       = submission.append_update!({'project' => {'title' => 'v2'}}, actor: 'test')

    assert_equal 'v1', submission.materialise_at(update_id: baseline.id).dig('project', 'title')
    assert_equal 'v2', submission.materialise_at(update_id: edit.id).dig('project', 'title')
    assert_equal 'v2', submission.materialise_at.dig('project', 'title')
  end

  test '#append_update! computes diff, appends, no-op when nothing changed' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'hello'}}, actor: 'curator')
    assert_equal 1, submission.updates.count

    again = submission.append_update!({'project' => {'title' => 'hello'}}, actor: 'curator')
    assert_nil again, 'identical record should produce empty diff and skip insert'
    assert_equal 1, submission.updates.count

    submission.append_update!({'project' => {'title' => 'world'}}, actor: 'curator')
    assert_equal 2, submission.updates.count
    assert_equal 'world', submission.materialised_record.dig('project', 'title')
  end

  test '#append_update! falls back to a root snapshot when diff lands inside a bag (e.g. submitter organizations)' do
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

    # Edit: add `url` to the existing organization. A minimal semantic
    # diff would emit `add /submission/submitters/0/organizations/0/url`
    # which descends into the `/submission/submitters/*/organizations`
    # bag — Canonicalizer rejects that as a BagPatchPathError. The
    # fallback emits a single root-level `replace` op instead so the
    # curator's save still lands.
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

    fallback_patch = submission.updates.order(:id).last.parsed_patch
    assert_equal 1, fallback_patch.size, 'bag-internal edit must coarsen to a single root op'
    assert_equal '',        fallback_patch.first['path']
    assert_equal 'replace', fallback_patch.first['op']

    assert_equal 'https://nig.ac.jp/',
                 submission.materialised_record.dig('submission', 'submitters', 0, 'organizations', 0, 'url')
  end

  test 'round-trip: apply(empty, diff(empty, R)) == R for 50 random records' do
    submission = Submission.create!(db: 'bioproject', user: users(:alice), source_id: "rt-#{SecureRandom.hex(4)}")
    50.times do |i|
      record = {
        'project' => {
          'accession'   => "PRJDB#{1000 + i}",
          'title'       => "title-#{SecureRandom.hex(3)}",
          'description' => "desc\nline2\nline3" * (i % 3 + 1)
        }
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
    submission.append_update!({'project' => {'title' => 'v0'}}, actor: 'seed')

    threads = 4.times.map {|i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          fresh = Submission.find(submission.id)
          fresh.append_update!({'project' => {'title' => "v#{i + 1}"}}, actor: "writer-#{i}")
        end
      end
    }
    threads.each(&:join)

    # All 4 appends must have landed; replay must succeed (no diverged chain).
    assert_equal 5, submission.updates.reload.count
    assert_includes %w[v0 v1 v2 v3 v4], submission.materialised_record.dig('project', 'title')
  end

  test 'write-through cache: first call attaches blob + stamps; second call returns from cache without replay' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'cached'}}, actor: 'test')

    assert_nil submission.reload.cached_at_update_id
    assert_not submission.cached_materialised_record.attached?

    first = submission.materialised_record
    assert_equal 'cached', first.dig('project', 'title')

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
    submission.append_update!({'project' => {'title' => 'v1'}}, actor: 'test')
    submission.materialised_record # warms cache

    assert submission.reload.cached_at_update_id.present?, 'baseline cache warm-up must populate cache'

    submission.append_update!({'project' => {'title' => 'v2'}}, actor: 'test')

    # SubmissionUpdate#after_create must have nil-cleared the cache stamp.
    assert_nil submission.reload.cached_at_update_id, 'append must invalidate cache'

    # Next read recomputes and re-stamps at the new latest.
    assert_equal 'v2', submission.materialised_record.dig('project', 'title')
    assert_equal submission.updates.reload.maximum(:id), submission.reload.cached_at_update_id
  end

  test 'write-through cache: invalidates when a SubmissionUpdate is destroyed' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'v1'}}, actor: 'test')
    second = submission.append_update!({'project' => {'title' => 'v2'}}, actor: 'test')
    submission.materialised_record # warms cache at v2
    assert submission.reload.cached_at_update_id.present?

    second.destroy!

    assert_nil submission.reload.cached_at_update_id,
               'after_destroy must invalidate cache when any update row is destroyed'
  end

  test 'materialise_at(update_id:) historical snapshots never consult the cache' do
    submission = submissions(:bioproject)
    first  = submission.append_update!({'project' => {'title' => 'v1'}}, actor: 'test')
    second = submission.append_update!({'project' => {'title' => 'v2'}}, actor: 'test')

    submission.materialised_record # populates cache at second.id

    # Cache is for "latest"; historical snapshots must replay so the
    # cache cannot serve the wrong-version data to a ?as_of query.
    assert_equal 'v1', submission.materialise_at(update_id: first.id).dig('project', 'title')
    assert_equal 'v2', submission.materialise_at(update_id: second.id).dig('project', 'title')
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
    30.times {|i| submission.append_update!({'project' => {'title' => "v#{i}"}}, actor: 'bench') }

    timings = Array.new(20) do
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      submission.materialised_record
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000
    end

    p99 = timings.sort[(timings.size * 0.99).ceil - 1]
    assert_operator p99, :<, 500, "30-patch p99 was #{p99.round(2)}ms"
  end
end
