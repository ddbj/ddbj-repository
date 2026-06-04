require 'test_helper'

class AdminSubmissionsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)
  end

  test 'index returns submissions across all DBs by default' do
    get admin_submissions_path

    assert_response :ok
    assert_match "Submission-#{submissions(:st26).id}",       response.body
    assert_match "Submission-#{submissions(:bioproject).id}", response.body
    assert_match "Submission-#{submissions(:biosample).id}",  response.body
  end

  test 'index filters by db' do
    get admin_submissions_path, params: {db: 'st26'}

    assert_response :ok
    assert_match    "Submission-#{submissions(:st26).id}",       response.body
    assert_no_match "Submission-#{submissions(:bioproject).id}", response.body
  end

  test 'index filters by user uid' do
    carol_request = SubmissionRequest.new(user: users(:carol), db: 'st26')
    attach_ddbj_record(carol_request)
    carol_request.save!

    carol_submission = Submission.new(db: 'st26', user: users(:carol), request: carol_request)
    attach_submission_files(carol_submission)
    carol_submission.save!

    get admin_submissions_path, params: {user: 'carol'}

    assert_response :ok
    assert_match    "Submission-#{carol_submission.id}",     response.body
    assert_no_match "Submission-#{submissions(:st26).id}",   response.body
  end

  test 'index shows BP Project.status + assignee for bioproject rows' do
    project = projects(:primary)
    project.update!(status: 'curating', assignee: users(:bob))

    get admin_submissions_path, params: {db: 'bioproject'}

    assert_response :ok
    body = css_select("tr a[href='#{admin_submission_path(submissions(:bioproject))}']").first
                                                                                       .ancestors('tr').first.to_s
    assert_match 'curating', body
    assert_match users(:bob).uid, body
  end

  test 'index shows BS Sample aggregate — uniform status / assignee surfaces directly' do
    samples(:first).update!(status: 'public',   assignee: users(:bob))
    samples(:second).update!(status: 'public',  assignee: users(:bob))

    get admin_submissions_path, params: {db: 'biosample'}

    assert_response :ok
    body = css_select("tr a[href='#{admin_submission_path(submissions(:biosample))}']").first
                                                                                      .ancestors('tr').first.to_s
    assert_match 'public', body
    assert_match users(:bob).uid, body
    refute_match(/Mixed/, body, 'uniform values must not be reported as Mixed')
  end

  test 'index shows BS Sample aggregate — mixed status surfaces as "Mixed (N)"' do
    samples(:first).update!(status: 'curating', assignee: users(:bob))
    samples(:second).update!(status: 'public',  assignee: users(:bob))

    get admin_submissions_path, params: {db: 'biosample'}

    body = css_select("tr a[href='#{admin_submission_path(submissions(:biosample))}']").first
                                                                                      .ancestors('tr').first.to_s
    assert_match 'Mixed (2)', body
  end

  test 'index shows "—" for ST26 (no curator status / assignee yet)' do
    get admin_submissions_path, params: {db: 'st26'}

    body = css_select("tr a[href='#{admin_submission_path(submissions(:st26))}']").first
                                                                                 .ancestors('tr').first.to_s
    assert_match '—', body
  end

  test 'index filters by source_id prefix (case-insensitive)' do
    submissions(:bioproject).update_columns(source_id: 'PSUB000604')
    submissions(:biosample).update_columns(source_id: 'SSUB002065')

    get admin_submissions_path, params: {source_id: 'psub'}

    assert_response :ok
    # Assert on the row href (id-based) so the test stays robust to
    # display-label changes (submission_label uses source_id when present).
    assert_match    admin_submission_path(submissions(:bioproject)), response.body
    assert_no_match admin_submission_path(submissions(:biosample)),  response.body
    assert_no_match admin_submission_path(submissions(:st26)),       response.body
  end

  test 'index filters by accession across projects (BP) / samples (BS) / accessions (ST26)' do
    # projects(:primary) has accession 'PRJDB000001' tied to submissions(:bioproject)
    # samples(:first) has accession 'SAMD00000001' tied to submissions(:biosample)
    # accessions(:one) has number 'ACC_000001' tied to submissions(:st26)

    get admin_submissions_path, params: {accession: 'PRJDB'}
    assert_match    "Submission-#{submissions(:bioproject).id}", response.body
    assert_no_match "Submission-#{submissions(:biosample).id}",  response.body
    assert_no_match "Submission-#{submissions(:st26).id}",       response.body

    get admin_submissions_path, params: {accession: 'SAMD'}
    assert_match    "Submission-#{submissions(:biosample).id}",  response.body
    assert_no_match "Submission-#{submissions(:bioproject).id}", response.body

    get admin_submissions_path, params: {accession: 'ACC_'}
    assert_match    "Submission-#{submissions(:st26).id}",       response.body
    assert_no_match "Submission-#{submissions(:bioproject).id}", response.body
  end

  test 'index treats SQL LIKE metacharacters in filter input as literals' do
    submissions(:bioproject).update_columns(source_id: 'PSUB000604')

    # If '%' were unescaped, this would match anything; sanitize_sql_like
    # should escape it so the literal '%' is required in source_id.
    get admin_submissions_path, params: {source_id: '%PSUB'}
    assert_no_match admin_submission_path(submissions(:bioproject)), response.body
  end

  test 'index escapes _ (single-char LIKE wildcard) in accession filter' do
    # Without sanitize_sql_like, `_` would match ANY single char, so the
    # filter 'ACC_' would also match this synthetic 'ACCX000001' on the
    # bioproject submission, leaking unrelated submissions into the list.
    # Accession.number has no format validator (unlike Sample/Project), so
    # we can attach a literal probe value to a non-st26 submission.
    submissions(:bioproject).accessions.create!(
      number:     'ACCX000001',
      entry_id:   'wildcard-probe',
      locus_date: Date.current
    )

    get admin_submissions_path, params: {accession: 'ACC_'}

    # accessions(:one) has number 'ACC_000001' (literal underscore) — must match
    assert_match    "Submission-#{submissions(:st26).id}",       response.body
    # 'ACCX000001' must NOT match — proves '_' was treated as a literal
    assert_no_match "Submission-#{submissions(:bioproject).id}", response.body
  end

  test 'index ignores non-String filter values instead of crashing on sanitize' do
    # An Array / Hash params shape used to reach sanitize_sql_like and
    # raise NoMethodError: undefined method 'gsub' for an instance of Array,
    # 500-ing the index. Now silently treated as no filter.
    get admin_submissions_path, params: {source_id: ['psub']}
    assert_response :ok

    get admin_submissions_path, params: {accession: {nested: 'x'}}
    assert_response :ok
  end

  test 'index caps filter input length to bound ILIKE cost / log payload' do
    submissions(:bioproject).update_columns(source_id: 'PSUB000604')

    # 70 chars > MAX_FILTER_LENGTH (64). The cap truncates input to the
    # 'PSUB' prefix (4 chars + 60 'A's truncated to 64 total) — still does
    # NOT match 'PSUB000604' because the truncated value contains 'A's
    # after the leading 'PSUB'.
    long_value = 'PSUB' + ('A' * 70)

    get admin_submissions_path, params: {source_id: long_value}
    assert_response :ok
    assert_no_match "Submission-#{submissions(:bioproject).id}", response.body
  end

  test 'index returns 403 for non-admin users' do
    sign_in_as users(:carol)

    with_exceptions_app do
      get admin_submissions_path
    end

    assert_response :forbidden
  end

  test 'show links to the materialised JSON endpoint and surfaces orientation metadata' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'accession' => 'PRJDB502', 'title' => 'hello'}}, actor: 'test')

    get admin_submission_path(submission)

    assert_response :ok
    assert_match "Submission-#{submission.id}",                          response.body
    assert_match 'View as JSON',                                         response.body
    assert_match materialised_admin_submission_path(submission),         response.body
    # Materialised content itself is no longer inlined — the body must
    # NOT contain the project payload.
    assert_no_match 'PRJDB502',                                          response.body
  end

  test 'show falls back gracefully when no updates have been applied' do
    submission = submissions(:bioproject)

    get admin_submission_path(submission)

    assert_response :ok
    assert_match 'nothing to materialise', response.body
  end

  test 'materialised returns the latest snapshot as JSON' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'first'}}, actor: 'test')
    submission.append_update!({'project' => {'title' => 'second'}}, actor: 'test')

    get materialised_admin_submission_path(submission)

    assert_response :ok
    assert_equal 'application/json', response.media_type
    body = JSON.parse(response.body)
    assert_equal 'second', body.dig('project', 'title')
  end

  test 'materialised ?as_of=N returns the snapshot at that update' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'v1'}}, actor: 'test')
    v2 = submission.append_update!({'project' => {'title' => 'v2'}}, actor: 'test')
    submission.append_update!({'project' => {'title' => 'v3'}}, actor: 'test')

    get materialised_admin_submission_path(submission, as_of: v2.id)

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 'v2', body.dig('project', 'title')
  end

  test 'materialised ?as_of=<latest_id> returns the same payload as no as_of' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'only'}}, actor: 'test')
    latest = submission.updates.last

    get materialised_admin_submission_path(submission)
    no_as_of = JSON.parse(response.body)

    get materialised_admin_submission_path(submission, as_of: latest.id)
    with_as_of = JSON.parse(response.body)

    assert_equal no_as_of, with_as_of
  end

  test 'materialised ?as_of=<unknown_id> 404s — stale link must not silently fall back' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'only'}}, actor: 'test')

    get materialised_admin_submission_path(submission, as_of: 999_999)
    assert_response :not_found
  end

  test 'materialised ?as_of=<non-numeric|0> falls through to latest (parse_as_of returns nil)' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'visible'}}, actor: 'test')

    get materialised_admin_submission_path(submission, as_of: 'foo')
    assert_response :ok
    assert_equal 'visible', JSON.parse(response.body).dig('project', 'title')

    get materialised_admin_submission_path(submission, as_of: 0)
    assert_response :ok
    assert_equal 'visible', JSON.parse(response.body).dig('project', 'title')
  end

  test 'materialised 404s when no updates have been applied' do
    submission = submissions(:bioproject)

    get materialised_admin_submission_path(submission)
    assert_response :not_found
  end

  test 'materialised ?as_of=N always replays (does NOT serve the bytea cache shortcut even when N == latest_id)' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'visible'}}, actor: 'test')
    latest = submission.updates.last
    submission.materialised_record # warm the cache

    # Pin the cache to a tampered value that differs from what
    # materialise_at would replay. If the action takes the cache shortcut
    # for ?as_of=<latest_id> the response will reflect the tampered cache;
    # if it always replays (the correct behaviour) the response reflects
    # the chain.
    submission.update_columns(cached_materialised_record: Oj.dump({'tampered' => true}, mode: :strict))

    get materialised_admin_submission_path(submission, as_of: latest.id)

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 'visible', body.dig('project', 'title'), 'explicit as_of must always replay, never serve cache'
    refute body.key?('tampered'), 'cache shortcut must not be taken when ?as_of= is supplied'
  end

  test 'materialised serves the cached bytea directly on the latest path (skipping Oj.load/re-encode roundtrip)' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'real'}}, actor: 'test')
    submission.materialised_record # warm the cache

    # If the action ships cached bytea directly, a sentinel inserted into
    # the bytea round-trips byte-for-byte. (Sibling test pins the OPPOSITE
    # behaviour for the ?as_of= path.)
    sentinel = Oj.dump({'cached_marker' => 'served-from-bytea'}, mode: :strict)
    submission.update_columns(cached_materialised_record: sentinel)

    get materialised_admin_submission_path(submission)

    assert_response :ok
    assert_equal 'served-from-bytea', JSON.parse(response.body)['cached_marker']
  end

  test 'materialised returns 422 + JSON error body on a poisoned patch chain' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'good'}}, actor: 'test')
    poisoned = submission.updates.create!(
      db:                      'bioproject',
      status:                  :applied,
      actor:                   'test',
      source:                  :manual,
      patch:                   'not-json',
      patch_canonical_version: 1
    )

    get materialised_admin_submission_path(submission)

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal 'replay_failed',  body['error']
    assert_equal poisoned.id,      body['update_id']
    assert_match(/parse/i,         body['message'])
  end

  test 'show skips canonical bytes / sha for records over the size limit (avoids 20s canonicalise)' do
    submission = submissions(:bioproject)
    # Synthesise a payload whose Oj.dump exceeds the 1 MB display limit.
    # A 2 MB string is plenty; Canonicalizer.canonicalize on this would
    # take seconds and dominate the show response.
    big_value = 'x' * (2 * 1024 * 1024)
    submission.append_update!({'project' => {'title' => 'big', 'description' => big_value}}, actor: 'test')

    get admin_submission_path(submission)

    assert_response :ok
    assert_match    'Skipped',                  response.body
    assert_match    'materialised record is',   response.body
    assert_no_match 'Canonical SHA-256',        response.body
  end

  test 'show computes canonical bytes / sha for records under the size limit' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'small'}}, actor: 'test')

    get admin_submission_path(submission)

    assert_response :ok
    assert_match    'Canonical bytes',   response.body
    assert_match    'Canonical SHA-256', response.body
    assert_no_match 'Skipped',           response.body
  end

  test 'show paginates samples inside a turbo-frame and supports ?samples_page= permalink' do
    submission = submissions(:biosample)
    # 30 fresh probes; combined with the 2 fixture samples that's 32
    # total — enough to cross the 20-per-page boundary (probe-017 ends
    # page 1 alongside the 2 fixtures, probe-018+ on page 2).
    30.times {|i| submission.samples.create!(sample_name: "probe-#{format('%03d', i)}", status: :public) }

    get admin_submission_path(submission)
    assert_response :ok
    assert_match    '<turbo-frame id="samples"',          response.body
    assert_match    'data-turbo-action="advance"',        response.body
    assert_match    'data-controller="frame-scroll-top"', response.body
    assert_match    'probe-000',                          response.body
    assert_no_match 'probe-025',                          response.body

    # Permalink — directly loading ?samples_page=2 lands on page 2.
    get admin_submission_path(submission, samples_page: 2)
    assert_response :ok
    assert_match    'probe-025',                          response.body
    assert_no_match 'probe-000',                          response.body

    # pagy links use the namespaced param so they don't collide with
    # a future paginator that might want plain ?page=.
    assert_match    'samples_page=',                      response.body
    assert_no_match(/[?&]page=\d/,                        response.body)
  end

  test 'show renders the Samples table for a biosample submission' do
    submission = submissions(:biosample)
    submission.samples.create!(
      accession:   'SAMD00099001',
      sample_name: 'DRS999001',
      package:     'Generic',
      status:      :public,
      organism:    'sample organism',
      taxonomy_id: 408170
    )
    submission.append_update!({'samples' => [{'accession' => 'SAMD00099001'}]}, actor: 'test')

    get admin_submission_path(submission)

    assert_response :ok
    assert_match 'Samples',         response.body
    assert_match 'SAMD00099001',    response.body
    assert_match 'sample organism', response.body
    assert_match 'DRS999001',       response.body
  end

  test 'show samples table renders Assignee column with per-sample uid' do
    submission = submissions(:biosample)
    samples(:first).update!(assignee: users(:bob))
    # samples(:second) intentionally left unassigned to pin the "—" case.

    get admin_submission_path(submission)

    assert_response :ok
    table_row_with_assignee = css_select('tbody tr').find {|tr| tr.css('td')[1]&.text == samples(:first).sample_name }
    assert_match users(:bob).uid, table_row_with_assignee.to_s,
                 'assigned sample row must show the assignee uid'

    table_row_without_assignee = css_select('tbody tr').find {|tr| tr.css('td')[1]&.text == samples(:second).sample_name }
    assert_match '—', table_row_without_assignee.css('td').last.text,
                 'unassigned sample row must show — in the Assignee cell'
  end

  test 'show survives a single poisoned patch — timeline renders, materialised pane reports the bad row' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'good'}}, actor: 'test')
    poisoned = submission.updates.create!(
      db:                       'bioproject',
      status:                   :applied,
      actor:                    'test',
      source:                   :manual,
      patch:                    'not-json',
      patch_canonical_version:  1
    )

    get admin_submission_path(submission)

    assert_response :ok
    assert_match    'Replay failed',                                       response.body
    assert_match    "##{poisoned.id}",                                     response.body
    assert_match    'patch unreadable',                                    response.body
    assert_no_match 'nothing to materialise',                              response.body
  end
end
