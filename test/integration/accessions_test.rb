require 'test_helper'

class AccessionsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)

    default_headers['Authorization'] = "Bearer #{@user.api_key}"
  end

  test 'show' do
    submission = submissions(:st26)

    attach_submission_files submission

    accession = submission.entries.first

    get accession_path(accession.accession)

    assert_conform_schema 200

    body = response.parsed_body

    assert_equal accession.accession, body['accession']
    assert_equal submission.id,    body.dig('submission', 'id')
    assert_not_nil                 body.dig('submission', 'flatfile_na', 'url')
  end

  test 'show returns 404 for unknown accession' do
    with_exceptions_app do
      get accession_path('UNKNOWN')
    end

    assert_conform_schema 404
  end

  test 'show returns 404 for accession owned by another user' do
    default_headers['Authorization'] = "Bearer #{users(:carol).api_key}"

    with_exceptions_app do
      get accession_path(submissions(:st26).entries.first.accession)
    end

    assert_conform_schema 404
  end

  # ddbj/submission-bulk-st26 builds the live list from this, and a
  # retracted entry has to be leavable out of it. Without the status the
  # list keeps an entry the flatfile has already dropped.
  test 'the status says whether the entry is still part of the submission' do
    submission = submissions(:st26)
    entry      = submission.entries.first

    attach_submission_files submission
    entry.update!(status: :withdrawn)

    get accession_path(entry.accession)

    assert_conform_schema 200
    assert_equal 'withdrawn', response.parsed_body['status']

    get submission_accessions_path(submission)

    assert_conform_schema 200

    row = response.parsed_body.find { it['accession'] == entry.accession }

    assert_equal 'withdrawn', row['status']
  end

  # This said "Accessions 0" and offered an empty list for every
  # BioProject and BioSample in the archive: the endpoint read `entries`,
  # and their numbers live on projects and samples.
  test "a BioProject's accession is its project's" do
    submission = submissions(:bioproject)

    get submission_accessions_path(submission)

    assert_conform_schema 200

    row = response.parsed_body.sole

    assert_equal projects(:primary).accession, row['accession']
    assert_equal 'bioproject',                 row['db']
    assert_equal 'Primary fixture project',    row['name']
    assert_equal 'Type',                       row['details'].sole['label']
  end

  test "a BioSample's accessions are its samples'" do
    submission = submissions(:biosample)

    get submission_accessions_path(submission)

    assert_conform_schema 200

    accessions = response.parsed_body.pluck('accession')

    assert_includes accessions, samples(:first).accession
    assert_equal 'biosample', response.parsed_body.first['db']

    # The sample without a number is not an accession, so it is not on a
    # list of them.
    assert_equal [samples(:first).accession], accessions
  end

  # Before the numbers are issued there is nothing to list, and the branch
  # that says so is the one this change added — `curation_rows` answers
  # nil for a BioProject with no project row.
  test 'a submission whose numbers have not been issued lists none' do
    submission = submissions(:bioproject)

    projects(:primary).update!(accession: nil)

    get submission_accessions_path(submission)

    assert_conform_schema 200
    assert_empty response.parsed_body

    projects(:primary).destroy!

    get submission_accessions_path(submission)

    assert_conform_schema 200
    assert_empty response.parsed_body
  end

  # Dropping an unknown value instead of refusing it would answer "which
  # of these are withdrawn" with every row there is, and a client cannot
  # tell that from a real answer.
  test 'the status filter works on every database, and refuses a value nobody knows' do
    submission = submissions(:biosample)

    samples(:first).update!(status: :withdrawn)

    get submission_accessions_path(submission, status: %w[withdrawn])

    assert_conform_schema 200
    assert_equal [samples(:first).accession], response.parsed_body.pluck('accession')

    get submission_accessions_path(submission, status: %w[public])

    assert_conform_schema 200
    assert_empty response.parsed_body

    # The contract already forbids the value, so the request is not checked
    # against the schema — the point is that the server refuses it too
    # rather than trusting a client to have read it.
    with_exceptions_app { get submission_accessions_path(submission, status: %w[withdrawn not_a_status]) }

    assert_response :bad_request
    assert_match(/not_a_status/, response.parsed_body['error'])
  end

  # As submitted, not by accession: ST.26 draws nucleotide and amino-acid
  # numbers from two sequences with disjoint prefixes, so sorting on the
  # number would split a submission into two blocks that appear nowhere
  # in its file.
  test 'the entries come back in the order they were submitted' do
    submission = submissions(:st26)

    later = submission.entries.create!(accession: 'ZAA0000001', entry_id: 'SEQ|3', locus_date: Date.new(2026, 1, 15))

    get submission_accessions_path(submission)

    assert_conform_schema 200
    assert_equal later.accession, response.parsed_body.last['accession']
    assert_equal submission.entries.order(:id).pluck(:accession), response.parsed_body.pluck('accession')
  end

  # The record laid out by its own shape. Nothing here names a field —
  # that is what lets a new v3 key appear the day it lands rather than
  # the day somebody revises a renderer.
  test "one accession's record comes back laid out by its shape" do
    submission = submissions(:biosample)
    sample     = samples(:first)

    submission.append_update!(
      {
        'samples' => [
          {
            # Found by alias, which is what every other join of this
            # array uses — a chain built by edits rather than by an
            # importer baseline carries no accession at all.
            'alias'      => sample.sample_name,
            'accession'  => sample.accession,
            'title'      => 'Control timepoint A',
            'organism'   => {'name' => 'mouse gut metagenome', 'taxonomy_id' => 410_661},
            'attributes' => [
              {'name' => 'collection_date', 'value' => '2018-04-25'},
              {'name' => 'env_broad_scale', 'value' => 'Gut'}
            ]
          }
        ]
      },
      actor: 'test'
    )

    get submission_accession_path(submission, sample.accession)

    assert_conform_schema 200

    body = response.parsed_body

    assert_equal sample.accession, body['accession']
    assert_nil   body['unavailable_reason']
    assert_equal false, body['elided']

    sections = body['sections'].index_by { it['key'] }

    assert_equal %w[accession alias attributes organism title], sections.keys.sort

    # A hash is rows of key and value.
    assert_equal 'fields', sections['organism']['node']['kind']
    assert_equal %w[name taxonomy_id], sections['organism']['node']['fields'].pluck('key')

    # An array of same-shaped hashes is a table, columns in the record's
    # own order.
    attributes = sections['attributes']['node']

    assert_equal 'table',           attributes['kind']
    assert_equal %w[name value],    attributes['columns']
    assert_equal 2,                 attributes['total']
    assert_equal 'collection_date', attributes['cells'].first.first['value']

    # And anything else is the value.
    assert_equal 'value',               sections['title']['node']['kind']
    assert_equal 'Control timepoint A', sections['title']['node']['value']
  end

  # Beside it in the record, not part of it. A sample is a sample's
  # fields; who submitted them is a fact about the submission.
  test "one accession's record carries nothing from beside it" do
    submission = submissions(:biosample)
    sample     = samples(:first)

    submission.append_update!(
      {
        'submission' => {'submitters' => [{'name' => 'A Person', 'email' => 'person@example.com'}]},
        'samples'    => [{'alias' => sample.sample_name, 'title' => 'Only this'}]
      },
      actor: 'test'
    )

    get submission_accession_path(submission, sample.accession)

    assert_conform_schema 200
    assert_equal %w[alias title], response.parsed_body['sections'].pluck('key').sort
    assert_not_includes response.body, 'person@example.com'
  end

  # Four ways there can be nothing to show, and telling one as another
  # sends somebody looking in the wrong place.
  test 'a record that does not carry the row says that, not that the database is unsupported' do
    submission = submissions(:biosample)
    sample     = samples(:first)

    submission.append_update!({'samples' => [{'alias' => 'somebody else', 'title' => 'Not it'}]}, actor: 'test')

    get submission_accession_path(submission, sample.accession)

    assert_conform_schema 200
    assert_equal Submission::RECORD_MISSING_ROW, response.parsed_body['unavailable_reason']
  end

  test 'a submission with no record yet says that' do
    submission = submissions(:biosample)

    get submission_accession_path(submission, samples(:first).accession)

    assert_conform_schema 200
    assert_equal Submission::RECORD_ABSENT, response.parsed_body['unavailable_reason']
  end

  # "This subtree is empty" and "this application cannot open that record
  # yet" are different answers, and drawing both as a blank panel tells
  # the second as the first.
  test 'a record this cannot read yet says so rather than looking empty' do
    submission = submissions(:st26)
    entry      = submission.entries.first

    get submission_accession_path(submission, entry.accession)

    assert_conform_schema 200
    assert_empty response.parsed_body['sections']
    assert_equal Submission::RECORD_NOT_READABLE_HERE, response.parsed_body['unavailable_reason']
  end

  # A BioProject's record is its project, and nothing in the suite
  # covered that branch.
  test "a BioProject's record is its project" do
    submission = submissions(:bioproject)

    submission.append_update!(
      {'project' => {'title' => 'Deep sea survey', 'project_type' => 'primary'}},
      actor: 'test'
    )

    get submission_accession_path(submission, projects(:primary).accession)

    assert_conform_schema 200
    assert_nil response.parsed_body['unavailable_reason']
    assert_equal %w[project_type title], response.parsed_body['sections'].pluck('key').sort
  end

  test 'an accession that is not this submission\'s is not found' do
    with_exceptions_app { get submission_accession_path(submissions(:biosample), 'PRJDB000001') }

    assert_conform_schema 404
  end

  # The count beside the link and the list behind it read the same rows.
  test 'the submission payload counts what the list holds' do
    submission = submissions(:biosample)

    attach_submission_files submission

    get submission_path(submission)

    assert_conform_schema 200

    counted = response.parsed_body['accessions_count']

    get submission_accessions_path(submission)

    assert_conform_schema 200
    assert_equal counted, response.parsed_body.size
    assert_operator counted, :>, 0
  end

  # A submission shared into a set opens for its members, and its
  # accessions are a large part of why anybody looks at a colleague's.
  test "a set member can read a colleague's accessions" do
    submission = submissions(:bioproject)
    alice      = users(:alice)
    carol      = users(:carol)

    set = SubmissionSet.create!(name: 'Deep sea study', owner: alice)
    set.inclusions.create!(submission_request: submission_requests(:bioproject), added_by: alice)
    set.members.create!(user: carol, invited_by: alice, joined_at: Time.current)

    default_headers['Authorization'] = "Bearer #{carol.api_key}"

    get submission_accessions_path(submission)

    assert_conform_schema 200
    assert_equal projects(:primary).accession, response.parsed_body.sole['accession']
  end

  test 'index spans every submission the user has' do
    get accessions_path

    assert_conform_schema 200

    assert_equal submissions(:st26).entries.pluck(:accession).sort,
                 response.parsed_body.pluck('accession').sort
  end

  # The reason the flat index exists: the entries whose status is no
  # longer the one they were issued with are a handful of rows in a table
  # of millions, and a client rebuilding its lists wants exactly those.
  test 'index narrows to the statuses asked for' do
    withdrawn = submissions(:st26).entries.first
    withdrawn.update! status: :withdrawn

    get accessions_path(status: %w[canceled withdrawn])

    assert_conform_schema 200

    assert_equal [withdrawn.accession], response.parsed_body.pluck('accession')
  end

  # Both directions, and with rows on both sides: carol owning nothing
  # would pass this even if the scoping were removed outright, and the
  # bug worth catching is the one that leaks some rows rather than all —
  # a join on the wrong key, or a `merge` that quietly drops the
  # `user_id` predicate.
  test 'the flat list is the caller\'s own entries and nobody else\'s' do
    mine   = submissions(:st26).entries.first
    theirs = Submission.create!(user: users(:carol), db: 'st26')
                       .entries.create!(accession: 'ACC_CAROL1', entry_id: 'C|1', version: 1, locus_date: Date.new(2026, 1, 15))

    get accessions_path

    assert_conform_schema 200

    accessions = response.parsed_body.pluck('accession')

    assert_includes     accessions, mine.accession
    assert_not_includes accessions, theirs.accession

    default_headers['Authorization'] = "Bearer #{users(:carol).api_key}"

    get accessions_path

    assert_conform_schema 200
    assert_equal [theirs.accession], response.parsed_body.pluck('accession')
  end

  # Same reasoning as the request list: intersecting and dropping the
  # filter would answer "which are retracted" with every entry there is,
  # and a client cannot tell that from a real answer.
  test 'index refuses a status it does not know' do
    with_exceptions_app do
      get accessions_path(status: %w[withdrawn not_a_status])
    end

    assert_response :bad_request
    assert_match(/not_a_status/, response.parsed_body['error'])
  end

  # The nested list is paged for a screen, the flat one for a sync. A sync
  # paged twenty at a time is what makes a whole retracted submission tens
  # of thousands of requests.
  test 'index pages the flat list far larger than the nested one' do
    submission = submissions(:st26)

    21.upto(60) do |i|
      submission.entries.create! accession: "ACC_#{i}", entry_id: "SEQ|#{i}", locus_date: Date.new(2026, 1, 15)
    end

    get submission_accessions_path(submission)

    assert_conform_schema 200
    assert_equal 20, response.parsed_body.size

    get accessions_path

    assert_conform_schema 200
    assert_equal submission.entries.count, response.parsed_body.size

    # The flat list is walked, not numbered: there is no total to count
    # down to, and the absence of a cursor is how a client knows to stop.
    assert_nil response.headers['Total-Pages']
    assert_nil response.headers['Next-Page']
  end

  # Offset pagination is wrong for a walk rather than merely slow: a row
  # disappearing from a page already read shifts every later row back by
  # one, and the row that crosses the page boundary is never returned. A
  # sync that silently skips a row is the failure this endpoint exists to
  # avoid.
  #
  # Inserts are not the hazard here — ids ascend, so a new row lands
  # after the cursor and cannot disturb what came before it. Deletions
  # are, and a submission destroyed mid-walk takes all of its entries.
  test 'walking the flat list misses nothing when rows disappear mid-walk' do
    submission = submissions(:st26)

    2.upto(2 * AccessionsController::SYNC_LIMIT) do |i|
      submission.entries.create! accession: format('ACC_%05d', i), entry_id: "SEQ|#{i}",
                                 locus_date: Date.new(2026, 1, 15)
    end

    seen    = []
    deleted = []
    cursor  = nil

    loop do
      get accessions_path(page: cursor)

      assert_conform_schema 200
      seen.concat response.parsed_body.pluck('accession')

      # A row on a page already read, removed before the next request. An
      # offset walk closes the gap by pulling everything after it back one
      # place, so the row on the far side of the boundary is stepped over.
      if (gone = submission.entries.order(:id).find { seen.include?(it.accession) && !deleted.include?(it.accession) })
        deleted << gone.accession
        gone.destroy!
      end

      break unless (cursor = response.headers['Next-Page'])
    end

    remaining = submission.entries.pluck(:accession)

    assert_empty remaining - seen, 'every row still there at the end was returned'
    assert_equal seen.uniq, seen, 'and none of them twice'
  end

  test 'index requires authentication' do
    default_headers.delete 'Authorization'

    with_exceptions_app do
      get accessions_path
    end

    assert_conform_schema 401
  end

  # Pagy decodes an unreadable cursor to nil and answers with page one,
  # which a walk cannot tell from its own first page — it would start
  # over and never finish, or finish having read the first page twice.
  test 'an unreadable page cursor is refused rather than restarted' do
    with_exceptions_app do
      get accessions_path(page: 'not-a-cursor')
    end

    assert_response :bad_request
  end
end
