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
                       .entries.create!(accession: 'ACC_CAROL1', entry_id: 'C|1', version: 1)

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
    assert_equal '1', response.headers['Total-Pages']
  end

  test 'index requires authentication' do
    default_headers.delete 'Authorization'

    with_exceptions_app do
      get accessions_path
    end

    assert_conform_schema 401
  end
end
