require 'test_helper'

# What the ledger's params mean and what the materialised endpoint
# returns — neither of which is anything a person does. How the ledger
# reads, and what its rows say, is test/system/submission_requests_test.rb;
# the Samples tab is test/system/workbench_test.rb.
class AdminSubmissionsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:bob)
  end

  test 'index returns submissions across all DBs by default' do
    get admin_submission_requests_path

    assert_response :ok
    assert_match admin_submission_request_path(submissions(:st26).request),       response.body
    assert_match admin_submission_request_path(submissions(:bioproject).request), response.body
    assert_match admin_submission_request_path(submissions(:biosample).request),  response.body
  end

  test 'index filters by db' do
    get admin_submission_requests_path, params: {db: 'st26'}

    assert_response :ok
    assert_match    admin_submission_request_path(submissions(:st26).request),       response.body
    assert_no_match admin_submission_request_path(submissions(:bioproject).request), response.body
  end

  test 'search matches a submitter uid on a submission-bearing request' do
    carol_request = SubmissionRequest.new(user: users(:carol), db: 'st26')
    attach_ddbj_record(carol_request)
    carol_request.save!

    carol_submission = Submission.new(db: 'st26', user: users(:carol), request: carol_request)
    attach_submission_files(carol_submission)
    carol_submission.save!

    get admin_submission_requests_path, params: {q: 'carol'}

    assert_response :ok
    assert_match    admin_submission_request_path(carol_submission.request),     response.body
    assert_no_match admin_submission_request_path(submissions(:st26).request),   response.body
  end

  # The uid half of the search joins to users, so it works on a request
  # that has no submission yet — where every other search input, which
  # correlates on submission_id, cannot match.
  test 'search matches a submitter uid on a request with no submission' do
    carol_request = SubmissionRequest.new(user: users(:carol), db: 'st26')
    attach_ddbj_record(carol_request)
    carol_request.save!

    get admin_submission_requests_path, params: {q: 'carol'}

    assert_response :ok
    assert_match    admin_submission_request_path(carol_request),              response.body
    assert_no_match admin_submission_request_path(submissions(:st26).request), response.body
  end

  test 'index filters by request status (pipeline)' do
    applied = SubmissionRequest.new(user: users(:alice), db: 'st26', status: :applied)
    attach_ddbj_record(applied)
    applied.save!

    get admin_submission_requests_path, params: {request_status: 'applied'}

    assert_response :ok
    assert_match    admin_submission_request_path(applied),                    response.body
    # Fixture requests default to waiting_validation, so they're excluded.
    assert_no_match admin_submission_request_path(submission_requests(:st26)), response.body
  end

  test 'index multi-selects OR the values within a filter (db array)' do
    get admin_submission_requests_path, params: {db: %w[st26 biosample]}

    assert_response :ok
    assert_match    admin_submission_request_path(submissions(:st26).request),       response.body
    assert_match    admin_submission_request_path(submissions(:biosample).request),  response.body
    assert_no_match admin_submission_request_path(submissions(:bioproject).request), response.body
  end

  test 'index assignee multi-select ORs "unassigned" and a specific user' do
    # users(:dave) is the second admin, so {0, bob} is a proper subset of
    # the universe — otherwise picking both would be "everything selected"
    # and the filter would (correctly) skip.
    submissions(:bioproject).request.assign!(users(:bob))
    submissions(:biosample).request.assign!(nil)
    submissions(:st26).request.assign!(users(:dave))

    get admin_submission_requests_path, params: {assignee: ['0', users(:bob).id.to_s]}

    assert_response :ok
    assert_match    admin_submission_request_path(submissions(:bioproject).request), response.body # via bob
    assert_match    admin_submission_request_path(submissions(:biosample).request),  response.body # via unassigned
    assert_no_match admin_submission_request_path(submissions(:st26).request),       response.body # dave
  end

  test 'index treats a fully-selected facet as no constraint (keeps pre-Apply requests)' do
    pending = SubmissionRequest.new(user: users(:alice), db: 'st26', status: :waiting_validation)
    attach_ddbj_record(pending)
    pending.save! # no submission → pre-Apply

    # Selecting EVERY curation status must not drop the pre-Apply request:
    # its submission-based EXISTS would exclude it, so a full facet skips.
    get admin_submission_requests_path, params: {status: Lifecycleable::STATUSES.keys}

    assert_response :ok
    assert_match admin_submission_request_path(pending), response.body
  end

  # The identifier a curator has in hand is as often "#19537" from a mail
  # subject as it is an accession, so a bare number is a request id.
  test 'search treats SQL LIKE metacharacters as literals' do
    submissions(:bioproject).update_columns(source_id: 'PSUB000604')

    # If '%' were unescaped, this would match anything; sanitize_sql_like
    # should escape it so the literal '%' is required in source_id.
    get admin_submission_requests_path, params: {q: '%PSUB'}
    assert_no_match admin_submission_request_path(submissions(:bioproject).request), response.body
  end

  test 'search escapes _ (single-char LIKE wildcard)' do
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

    get admin_submission_requests_path, params: {q: 'ACC_'}

    # accessions(:one) has number 'ACC_000001' (literal underscore) — must match
    assert_match    admin_submission_request_path(submissions(:st26).request),       response.body
    # 'ACCX000001' must NOT match — proves '_' was treated as a literal
    assert_no_match admin_submission_request_path(submissions(:bioproject).request), response.body
  end

  test 'search ignores non-String values instead of crashing on sanitize' do
    # An Array / Hash params shape used to reach sanitize_sql_like and
    # raise NoMethodError: undefined method 'gsub' for an instance of Array,
    # 500-ing the index. Now silently treated as no filter.
    get admin_submission_requests_path, params: {q: ['psub']}
    assert_response :ok

    get admin_submission_requests_path, params: {q: {nested: 'x'}}
    assert_response :ok
  end

  test 'search caps input length to bound ILIKE cost / log payload' do
    submissions(:bioproject).update_columns(source_id: 'PSUB000604')

    # 70 chars > MAX_QUERY_LENGTH (64). The cap truncates input to the
    # 'PSUB' prefix (4 chars + 60 'A's truncated to 64 total) — still does
    # NOT match 'PSUB000604' because the truncated value contains 'A's
    # after the leading 'PSUB'.
    long_value = 'PSUB' + ('A' * 70)

    get admin_submission_requests_path, params: {q: long_value}
    assert_response :ok
    assert_no_match admin_submission_request_path(submissions(:bioproject).request), response.body
  end

  test 'index returns 403 for non-admin users' do
    sign_in_as users(:carol)

    with_exceptions_app do
      get admin_submission_requests_path
    end

    assert_response :forbidden
  end

  test 'the record tab links to the materialised JSON endpoint and surfaces orientation metadata' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'accession' => 'PRJDB502', 'title' => 'hello'}}, actor: 'test')

    get record_admin_submission_request_path(submission.request)

    assert_response :ok
    assert_match admin_submission_request_path(submission.request), response.body
    assert_match 'View as JSON',                                    response.body
    assert_match materialised_admin_submission_path(submission),    response.body

    # The materialised record is linked, not inlined — the size and digest
    # orient the curator, the JSON itself is one click away.
    assert_match 'Canonical SHA-256', response.body
    assert_no_match(/View as JSON.*\{/m, response.body)
  end

  # Under ddbj-canon/v1 an accession was stripped from both sides of every
  # diff, so this patch would have carried only the title.
  test 'the chain records an accession like any other record field' do
    submission = submissions(:bioproject)
    update     = submission.append_update!({'project' => {'accession' => 'PRJDB502', 'title' => 'hello'}}, actor: 'test')

    assert_equal 'PRJDB502', submission.materialised_record.dig('project', 'accession')
    assert_includes Oj.dump(update.parsed_patch, mode: :strict), 'PRJDB502',
                    'the accession must reach the patch, whatever shape the diff takes'
  end

  test 'the record tab falls back gracefully when no updates have been applied' do
    submission = submissions(:bioproject)

    get record_admin_submission_request_path(submission.request)

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

  test 'materialised ?as_of=N always replays (does NOT serve the cached blob shortcut even when N == latest_id)' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'visible'}}, actor: 'test')
    latest = submission.updates.last
    submission.materialised_record # warm the cache

    # Pin the cache to a tampered value that differs from what
    # materialise_at would replay. If the action takes the cache shortcut
    # for ?as_of=<latest_id> the response will reflect the tampered cache;
    # if it always replays (the correct behaviour) the response reflects
    # the chain.
    submission.prime_cache!(bytes: Oj.dump({'tampered' => true}, mode: :strict), update_id: latest.id)

    get materialised_admin_submission_path(submission, as_of: latest.id)

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal 'visible', body.dig('project', 'title'), 'explicit as_of must always replay, never serve cache'
    refute body.key?('tampered'), 'cache shortcut must not be taken when ?as_of= is supplied'
  end

  test 'materialised serves the cached blob bytes directly on the latest path (skipping Oj.load/re-encode roundtrip)' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'real'}}, actor: 'test')
    submission.materialised_record # warm the cache
    latest = submission.updates.last

    # If the action ships cached bytes directly, a sentinel attached to
    # the blob round-trips byte-for-byte. (Sibling test pins the OPPOSITE
    # behaviour for the ?as_of= path.)
    sentinel = Oj.dump({'cached_marker' => 'served-from-cache'}, mode: :strict)
    submission.prime_cache!(bytes: sentinel, update_id: latest.id)

    get materialised_admin_submission_path(submission)

    assert_response :ok
    assert_equal 'served-from-cache', JSON.parse(response.body)['cached_marker']
  end

  test 'materialised returns 422 + JSON error body on a poisoned patch chain' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'good'}}, actor: 'test')
    poisoned = SubmissionUpdate.create_with_patch!(
      submission:              submission,
      patch_json:              'not-json',
      db:                      'bioproject',
      status:                  :applied,
      actor:                   'test',
      source:                  :manual,
      patch_canonical_version: 1
    )

    get materialised_admin_submission_path(submission)

    assert_response :unprocessable_content
    body = JSON.parse(response.body)
    assert_equal 'replay_failed',  body['error']
    assert_equal poisoned.id,      body['update_id']
    assert_match(/parse/i,         body['message'])
  end

  test 'the record tab skips canonical bytes / sha over the size limit (avoids 20s canonicalise)' do
    submission = submissions(:bioproject)
    # Synthesise a payload whose Oj.dump exceeds the 1 MB display limit.
    # A 2 MB string is plenty; Canonicalizer.canonicalize on this would
    # take seconds and dominate the show response.
    big_value = 'x' * (2 * 1024 * 1024)
    submission.append_update!({'project' => {'title' => 'big', 'description' => big_value}}, actor: 'test')

    get record_admin_submission_request_path(submission.request)

    assert_response :ok
    assert_match    'Skipped',                  response.body
    assert_match    'materialised record is',   response.body
    assert_no_match 'Canonical SHA-256',        response.body
  end

  test 'the record tab computes canonical bytes / sha for records under the size limit' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'small'}}, actor: 'test')

    get record_admin_submission_request_path(submission.request)

    assert_response :ok
    assert_match    'Canonical bytes',   response.body
    assert_match    'Canonical SHA-256', response.body
    assert_no_match 'Skipped',           response.body
  end

  # Pagination has to carry the filter, or clicking page 2 silently widens
  # the set the curator thought they were working through.
  test 'the record tab survives a single poisoned patch — the chain renders and names the bad row' do
    submission = submissions(:bioproject)
    submission.append_update!({'project' => {'title' => 'good'}}, actor: 'test')
    poisoned = SubmissionUpdate.create_with_patch!(
      submission:              submission,
      patch_json:              'not-json',
      db:                      'bioproject',
      status:                  :applied,
      actor:                   'test',
      source:                  :manual,
      patch_canonical_version: 1
    )

    get record_admin_submission_request_path(submission.request)

    assert_response :ok
    assert_match    'Replay failed',                                       response.body
    assert_match    "##{poisoned.id}",                                     response.body
    assert_match    'patch unreadable',                                    response.body
    assert_no_match 'nothing to materialise',                              response.body
  end
end
