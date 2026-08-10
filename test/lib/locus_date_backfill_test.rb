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
  # spells some other way is left alone rather than guessed at.
  test 'a date that is not YYYY-MM-DD leaves the entry alone' do
    assert_nil LocusDateBackfill.parse('8/13')
    assert_nil LocusDateBackfill.parse('2026-225')
    assert_nil LocusDateBackfill.parse(nil)
    assert_equal Date.new(2026, 8, 13), LocusDateBackfill.parse('2026-08-13')
  end

  private

  # The apply job stamps the column with the apply date when the record names no
  # date; `setup` then moves it to something else to make the legacy shape, so
  # the "still bears the apply stamp" test has to compare against created_at.
  def apply_date = @submission.entries.first.created_at.to_date

  def outcome(**) = LocusDateBackfill.each_submission(**).find { it.submission == @submission }

  def build_request(locus_date)
    record = JSON.parse(file_fixture('ddbj_record/example.json').read)

    record['sequences']['entries'].each { it['locus_date'] = locus_date }

    SubmissionRequest.new(user: users(:alice), db: 'st26').tap do |request|
      request.ddbj_record.attach(
        io:           StringIO.new(JSON.generate(record)),
        filename:     'example.json',
        content_type: 'application/json'
      )

      request.save!
    end
  end
end
