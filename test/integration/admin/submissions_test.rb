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

  test 'index filters by source_id prefix (case-insensitive)' do
    submissions(:bioproject).update_columns(source_id: 'PSUB000604')
    submissions(:biosample).update_columns(source_id: 'SSUB002065')

    get admin_submissions_path, params: {source_id: 'psub'}

    assert_response :ok
    assert_match    "Submission-#{submissions(:bioproject).id}", response.body
    assert_no_match "Submission-#{submissions(:biosample).id}",  response.body
    assert_no_match "Submission-#{submissions(:st26).id}",       response.body
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
    assert_no_match "Submission-#{submissions(:bioproject).id}", response.body
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

  test 'show renders the materialised v3 record' do
    submission = submissions(:bioproject)
    record     = {'project' => {'accession' => 'PRJDB502', 'title' => 'hello'}}
    submission.updates.create!(
      db:                       'bioproject',
      status:                   :applied,
      actor:                    'migration:test',
      source:                   :migration,
      patch:                    Oj.dump([{'op' => 'add', 'path' => '', 'value' => record}], mode: :strict),
      patch_canonical_version:  1
    )

    get admin_submission_path(submission)

    assert_response :ok
    assert_match "Submission-#{submission.id}", response.body
    assert_match 'PRJDB502',                    response.body
    assert_match 'hello',                       response.body
  end

  test 'show falls back gracefully when no updates have been applied' do
    submission = submissions(:bioproject)

    get admin_submission_path(submission)

    assert_response :ok
    assert_match 'nothing to materialise', response.body
  end

  test 'show ?as_of=N renders the snapshot at that update' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'v1'}}, actor: 'test')
    v2 = submission.append_update!({'project' => {'title' => 'v2'}}, actor: 'test')
    submission.append_update!({'project' => {'title' => 'v3'}}, actor: 'test')

    get admin_submission_path(submission, as_of: v2.id)

    assert_response :ok
    assert_match    'Viewing snapshot at',  response.body
    assert_match    'v2',                   response.body
    assert_no_match(/"title":\s*"v3"/,      response.body)
  end

  test 'show ?as_of=<latest_id> behaves like no as_of (no snapshot banner)' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'v1'}}, actor: 'test')
    latest = submission.append_update!({'project' => {'title' => 'v2'}}, actor: 'test')

    get admin_submission_path(submission, as_of: latest.id)

    assert_response :ok
    assert_no_match 'Viewing snapshot at', response.body
    assert_no_match 'not found on this submission', response.body
    assert_match    'v2',                            response.body
  end

  test 'show ?as_of=999999 warns and shows latest' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'only'}}, actor: 'test')

    get admin_submission_path(submission, as_of: 999_999)

    assert_response :ok
    assert_match 'not found on this submission', response.body
    assert_match 'only',                         response.body
  end

  test 'show ?as_of=foo (non-numeric) is treated as no cutoff and shows latest without a warning' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'visible'}}, actor: 'test')

    get admin_submission_path(submission, as_of: 'foo')

    assert_response :ok
    assert_no_match 'not found on this submission', response.body
    assert_no_match 'nothing to materialise',       response.body
    assert_match    'visible',                      response.body
  end

  test 'show ?as_of=0 is rejected and shows latest without a warning' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'visible'}}, actor: 'test')

    get admin_submission_path(submission, as_of: 0)

    assert_response :ok
    assert_no_match 'not found on this submission', response.body
    assert_no_match 'nothing to materialise',       response.body
    assert_match    'visible',                      response.body
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
    # 60 samples crosses the 50-per-page boundary, exercising page 2.
    60.times {|i| submission.samples.create!(sample_name: "probe-#{format('%03d', i)}", status: :public) }

    # Page 1: probe-000 visible, probe-050 (page 2) not.
    get admin_submission_path(submission)
    assert_response :ok
    assert_match    '<turbo-frame id="samples"',                                       response.body
    assert_match    'data-turbo-action="advance"',                                     response.body
    assert_match    'probe-000',                                                       response.body
    assert_no_match 'probe-050',                                                       response.body

    # Permalink — directly loading ?samples_page=2 lands on page 2.
    get admin_submission_path(submission, samples_page: 2)
    assert_response :ok
    assert_match    'probe-050',                                                       response.body
    assert_no_match 'probe-000',                                                       response.body

    # pagy links use the namespaced param so they don't collide with
    # a future paginator that might want plain ?page=.
    assert_match    'samples_page=',                                                   response.body
    assert_no_match(/[?&]page=\d/,                                                     response.body)
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
