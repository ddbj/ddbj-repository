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

  test 'write-through cache: first call computes + persists; second call returns from column without replay' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'cached'}}, actor: 'test')

    assert_nil submission.reload.cached_at_update_id
    assert_nil submission.cached_materialised_record

    first = submission.materialised_record
    assert_equal 'cached', first.dig('project', 'title')

    submission.reload
    assert submission.cached_materialised_record.present?, 'cache bytea must be written through'
    assert_equal submission.updates.maximum(:id), submission.cached_at_update_id

    # On the cache hit path, do not invoke the replay engine. Stubbing
    # Canonicalizer.apply to raise asserts the bypass without depending
    # on the patch column's evolving integrity rules (DB CHECK
    # constraints, future BEFORE-UPDATE triggers, etc.).
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

    # SubmissionUpdate#after_create_commit must have nil-cleared cache.
    assert_nil submission.reload.cached_at_update_id, 'append must invalidate cache'
    assert_nil submission.cached_materialised_record

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
               'after_destroy_commit must invalidate cache when any update row is destroyed'
    assert_nil submission.cached_materialised_record
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
