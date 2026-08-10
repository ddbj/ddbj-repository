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
    @submission.entries.update_all(locus_date: Date.new(2026, 7, 7))
  end

  test 'moves the column back to the date the request asked for' do
    result = LocusDateBackfill.audit

    assert_equal [[Date.new(2026, 7, 7), Date.new(2026, 7, 11)]], result.changes.map { [it.from, it.to] }.uniq

    LocusDateBackfill.apply! result.changes

    assert_equal [Date.new(2026, 7, 11)], @submission.entries.reload.distinct.pluck(:locus_date)
  end

  test 'leaves alone an entry named in except' do
    kept = @submission.entries.order(:accession).first

    result = LocusDateBackfill.audit(except: kept.accession)

    refute_includes result.changes.map { it.entry.id }, kept.id
    assert_equal Date.new(2026, 7, 7), kept.reload.locus_date
  end

  test 'finds nothing once the column already agrees' do
    LocusDateBackfill.apply! LocusDateBackfill.audit.changes

    assert_empty LocusDateBackfill.audit.changes
  end

  # The audit and the write are separate reads. A date that moved in between is
  # one this no longer knows the truth about, so the run stops rather than
  # overwriting the newer value.
  test 'refuses to write when the date moved since the audit' do
    changes = LocusDateBackfill.audit.changes

    @submission.entries.update_all(locus_date: Date.new(2026, 8, 13))

    assert_raises RuntimeError do
      LocusDateBackfill.apply! changes
    end

    assert_equal [Date.new(2026, 8, 13)], @submission.entries.reload.distinct.pluck(:locus_date)
  end

  test 'a request with no record is reported rather than passed over' do
    @request.ddbj_record.purge

    result = LocusDateBackfill.audit
    mine   = result.unexamined.find { it.submission == @submission }

    assert mine, 'the submission whose request lost its record was passed over silently'
    assert_equal 'request has no record', mine.why
    assert_empty result.changes
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
