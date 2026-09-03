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
    assert_equal submission.samples.where.not(accession: nil).count, accessions.size
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
