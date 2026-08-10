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

    updates = []

    capture_updates(updates) { LocusDateBackfill.apply! changes }

    assert_equal 1, updates.size, "expected one UPDATE, got #{updates.size}"
    assert_equal [Date.new(2026, 7, 11)], @submission.entries.reload.distinct.pluck(:locus_date)
  end

  # The shape the ids exist for. Three entries sharing the apply stamp: A and B
  # are to be moved, C is held back because its request names no date at all. A
  # then moves off that date before the write.
  #
  # Naming the submission and the date in the WHERE, and trusting a row count to
  # prove identity, would find two rows on the date — B and C — count them equal
  # to the two it meant to write, and overwrite C. Silently, and reported as
  # success. With the ids in the WHERE only B is hit, the count no longer matches,
  # and nothing is written.
  test 'a change set that no longer matches the rows writes none of them' do
    submission = seed_submission(['2026-07-11', '2026-07-11', nil])
    a, b, c    = submission.entries.order(:accession).to_a
    stamp      = a.locus_date
    changes    = outcome(submission).changes

    assert_equal [a.id, b.id], changes.map { it.entry.id }
    assert_equal stamp, c.locus_date, 'C has to share the date being moved off for this to be the real case'

    a.update! locus_date: Date.new(2026, 9, 1)

    assert_raises RuntimeError do
      LocusDateBackfill.apply! changes
    end

    assert_equal Date.new(2026, 9, 1), a.reload.locus_date
    assert_equal stamp,                b.reload.locus_date, 'B was written although the change set no longer held'
    assert_equal stamp,                c.reload.locus_date, 'C was swept in by the batch'
  end

  # An entry held back for a reason that has nothing to do with its date still
  # carries the apply stamp and shares it with the ones being moved.
  test 'a held-back entry sharing the same date is not written' do
    submission = seed_submission(['2026-07-11', nil])
    moved, held = submission.entries.order(:accession).to_a
    stamp       = held.locus_date
    changes     = outcome(submission).changes

    assert_equal [moved.id], changes.map { it.entry.id }
    assert_equal stamp, changes.sole.from

    LocusDateBackfill.apply! changes

    assert_equal Date.new(2026, 7, 11), moved.reload.locus_date
    assert_equal stamp,                 held.reload.locus_date, 'the held-back entry was written'
  end

  # BATCH is 2,000 and a fixture has a handful of entries, so nothing would
  # otherwise cross a slice boundary.
  test 'a change set larger than one slice is written in several statements' do
    changes = outcome.changes

    assert_equal 2, changes.size

    updates = []

    with_batch 1 do
      capture_updates(updates) { LocusDateBackfill.apply! changes }
    end

    assert_equal 2, updates.size, 'expected one statement per slice'
    assert_equal [Date.new(2026, 7, 11)], @submission.entries.reload.distinct.pluck(:locus_date)
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

  def outcome(submission = @submission, **) = LocusDateBackfill.each_submission(**).find { it.submission == submission }

  # A submission whose request names one date per entry (nil for "no date"),
  # applied and then put into the legacy shape: the column carrying the apply
  # date, which is what the job wrote before it read the record.
  def seed_submission(dates)
    request = SubmissionRequest.new(user: users(:alice), db: 'st26')
    record  = JSON.parse(file_fixture('ddbj_record/example.json').read)
    entry   = record['sequences']['entries'].first

    record['sequences']['entries'] = dates.each_with_index.map {|date, i|
      entry.merge('id' => "SEQ|JP|2026123456|B|#{i + 1}", 'locus_date' => date)
    }

    request.ddbj_record.attach(io: StringIO.new(JSON.generate(record)), filename: 'example.json', content_type: 'application/json')
    request.save!

    ApplySubmissionRequestJob.perform_now request

    request.reload.submission.tap {|s| s.entries.update_all(locus_date: s.entries.first.created_at.to_date) }
  end

  def capture_updates(into, &)
    listener = ->(_, _, _, _, payload) { into << payload[:sql] if payload[:sql].start_with?('UPDATE') }

    ActiveSupport::Notifications.subscribed(listener, 'sql.active_record', &)
  end

  def with_batch(size)
    original = LocusDateBackfill::BATCH

    LocusDateBackfill.send :remove_const, :BATCH
    LocusDateBackfill.const_set :BATCH, size

    yield
  ensure
    LocusDateBackfill.send :remove_const, :BATCH
    LocusDateBackfill.const_set :BATCH, original
  end

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
