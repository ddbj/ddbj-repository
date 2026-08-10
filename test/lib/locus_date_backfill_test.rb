require 'test_helper'

# The repair behind `rake locus_date:backfill`. Covered because it writes a date
# that gets printed on published flatfiles, and because the case it must NOT
# touch — an entry deliberately redated away from what its request asked for —
# is the one that would undo the PATENT-386 correction.
class LocusDateBackfillTest < ActiveSupport::TestCase
  setup do
    # A request whose record names 2026-07-11, applied while the job still wrote
    # the apply date into the column: the shape of every legacy submission.
    @request = build_request('2026-07-11')

    ApplySubmissionRequestJob.perform_now @request

    @submission = @request.reload.submission

    # The legacy shape: the column carries the apply date (which is what the job
    # wrote before it started reading the record), the record carries 2026-07-11.
    @submission.entries.update_all(locus_date: @submission.entries.first.created_at.to_date)
  end

  test 'moves the column back to the date the request asked for' do
    changes = outcome.changes

    assert_equal [[apply_date, Date.new(2026, 7, 11)]], changes.map { [it.from, it.to] }.uniq

    LocusDateBackfill.apply! changes

    assert_equal [Date.new(2026, 7, 11)], @submission.entries.reload.distinct.pluck(:locus_date)
  end

  # 9.8M entries means a statement each is nine million round trips. Written in
  # one go when the group is every entry of the submission carrying that date.
  test 'a whole submission is redated in one statement' do
    changes = outcome.changes

    assert_equal 2, changes.size

    queries = []
    sub     = ->(_, _, _, _, payload) { queries << payload[:sql] if payload[:sql].start_with?('UPDATE') }

    ActiveSupport::Notifications.subscribed(sub, 'sql.active_record') do
      LocusDateBackfill.apply! changes
    end

    assert_equal 1, queries.size, "expected one UPDATE, got #{queries.size}"
    assert_equal [Date.new(2026, 7, 11)], @submission.entries.reload.distinct.pluck(:locus_date)
  end

  # The dangerous shape: an entry held back for a reason that has nothing to do
  # with its date, so it still carries the apply stamp and shares it with the
  # entries being moved. Naming the submission and the date in the WHERE — and
  # trusting a row count to prove identity — would sweep it in. The ids are what
  # make that impossible.
  test 'a held-back entry sharing the same date is not swept into the batch' do
    @request.ddbj_record.purge
    attach_record @request, ['2026-07-11', '2026-8-13'] # the second cannot be read

    held    = @submission.entries.order(:accession).last
    changes = outcome.changes

    assert_equal 1, changes.size
    assert_equal held.locus_date, changes.sole.from, 'the held-back entry shares the date being moved off'

    LocusDateBackfill.apply! changes

    assert_equal Date.new(2026, 7, 11), @submission.entries.order(:accession).first.reload.locus_date
    assert_equal held.locus_date,       held.reload.locus_date, 'the held-back entry was overwritten'
  end

  # And the same, one layer down: whatever moves under it between the read and
  # the write, only the rows that were read can be touched.
  test 'a row that moved onto the date since it was read is left alone' do
    changes = outcome.changes
    moved   = @submission.entries.order(:accession).last

    # The audit read both; take one out of the change set, and move it away and
    # back so the count would still match a submission-and-date WHERE.
    changes = changes.reject { it.entry.id == moved.id }

    LocusDateBackfill.apply! changes

    assert_equal Date.new(2026, 7, 11), @submission.entries.order(:accession).first.reload.locus_date
    assert_equal changes.sole.from,     moved.reload.locus_date, 'a row outside the change set was written'
  end

  # An entry whose date was set on purpose no longer carries the apply stamp, and
  # restoring "what the request asked for" over it would undo that decision —
  # PATENT-386's five, redated to 2026-08-13, are why this matters. No list of
  # exceptions to remember.
  test 'leaves alone an entry whose date was set deliberately' do
    kept = @submission.entries.order(:accession).first

    kept.update! locus_date: Date.new(2026, 8, 13)

    refute_includes outcome.changes.map { it.entry.id }, kept.id
  end

  # ACCESSIONS reaches whole submissions to find the records; restoring the
  # siblings was not what was asked for.
  test 'only the named accessions are moved' do
    named, sibling = @submission.entries.order(:accession).to_a

    changes = outcome(accessions: named.accession).changes

    assert_equal [named.id], changes.map { it.entry.id }
    refute_includes changes.map { it.entry.id }, sibling.id
  end

  test 'finds nothing once the column already agrees' do
    LocusDateBackfill.apply! outcome.changes

    assert_empty outcome.changes
  end

  # The audit and the write are separate reads. A date that moved in between is
  # one this no longer knows the truth about, so the run stops rather than
  # overwriting the newer value.
  test 'refuses to write when the date moved since it was read' do
    changes = outcome.changes

    @submission.entries.update_all(locus_date: Date.new(2026, 8, 13))

    assert_raises RuntimeError do
      LocusDateBackfill.apply! changes
    end

    assert_equal [Date.new(2026, 8, 13)], @submission.entries.reload.distinct.pluck(:locus_date)
  end

  test 'a request with no record is reported rather than passed over' do
    @request.ddbj_record.purge

    mine = outcome

    refute_predicate mine, :examined?
    assert_equal 'request has no record', mine.unexamined
    assert_empty mine.changes
  end

  test 'LIMIT and AFTER refuse anything that is not a number' do
    assert_raises ArgumentError do
      LocusDateBackfill.each_submission(after: 'LC000123').to_a
    end

    assert_raises ArgumentError do
      LocusDateBackfill.each_submission(limit: 'all').to_a
    end
  end

  # `Date.parse` would read `8/13` as this year's 13 August. A date the record
  # spells some other way is not guessed at — and is told apart from a record
  # that names no date at all, which is nothing to report.
  test 'a date that is not YYYY-MM-DD is unreadable rather than absent' do
    assert_equal :unreadable, LocusDateBackfill.parse('8/13')
    assert_equal :unreadable, LocusDateBackfill.parse('2026-225')
    assert_nil LocusDateBackfill.parse(nil)
    assert_nil LocusDateBackfill.parse('')
    assert_equal Date.new(2026, 8, 13), LocusDateBackfill.parse('2026-08-13')
  end

  # Left alone, but named: the column stays on the apply date, so the guard will
  # refuse the submission and somebody has to look at it.
  test 'an unreadable original date is reported, not skipped in silence' do
    @request.ddbj_record.purge
    attach_record @request, '2026-8-13'

    mine = outcome

    assert_empty mine.changes
    assert_equal @submission.entries.order(:accession).map(&:accession), mine.unreadable
    assert_predicate mine, :needs_attention?
  end

  # Its record and its published flatfile already carry the apply date, so moving
  # only the column would leave it disagreeing with itself — and unregeneratable.
  test 'a submission that has already been regenerated is refused, not backfilled' do
    EntryHistory.create! entry: @submission.entries.first, user: users(:alice), action: 'regenerate'

    mine = outcome

    refute_predicate mine, :examined?
    assert_match(/already regenerated/, mine.unexamined)
    assert_empty mine.changes
  end

  # 意図して設定された日付は報告される (黙って飛ばさない)。
  test 'an entry dated by hand is named in the report' do
    kept = @submission.entries.order(:accession).first

    kept.update! locus_date: Date.new(2026, 8, 13)

    assert_includes outcome.deliberate, kept.accession
  end

  private

  # The apply job stamps the column with the apply date when the record names no
  # date; `setup` then moves it to something else to make the legacy shape, so
  # the "still bears the apply stamp" test has to compare against created_at.
  def apply_date = @submission.entries.first.created_at.to_date

  def outcome(**) = LocusDateBackfill.each_submission(**).find { it.submission == @submission }

  def build_request(locus_date)
    SubmissionRequest.new(user: users(:alice), db: 'st26').tap do |request|
      attach_record request, locus_date
      request.save!
    end
  end

  # `locus_date` may be one value for every entry, or one per entry in order.
  def attach_record(request, locus_date)
    record = JSON.parse(file_fixture('ddbj_record/example.json').read)
    dates  = Array(locus_date)

    record['sequences']['entries'].each_with_index {|entry, i| entry['locus_date'] = dates[i] || dates.first }

    request.ddbj_record.attach(
      io:           StringIO.new(JSON.generate(record)),
      filename:     'example.json',
      content_type: 'application/json'
    )
  end
end
