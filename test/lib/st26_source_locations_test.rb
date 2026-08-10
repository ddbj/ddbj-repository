require 'test_helper'

# The audit and correction behind `rake st26:source_locations:*`. Covered
# because it is the only code in this change that rewrites an archived record,
# and because two of its rules exist to undo specific regressions: the count
# guard has to fire before anything is written, and a record that was not
# examined must not be reported as a clean one.
class St26SourceLocationsTest < ActiveSupport::TestCase
  # The whole point of the classification: only the JPO defect is repaired
  # automatically, because only there is `1..<length>` plainly what was meant.
  #
  # `<1..>21` and `J00194.1:1..21` matter most — bio-ruby keeps the partiality
  # markers and the cross-referenced accession beside the numbers, so a check
  # reading only `from` and `to` calls them plain ranges and rewriting throws
  # them away.
  {
    '1..20'             => nil,
    'join(1..4,6..20)'  => nil,        # covers the whole sequence, gap and all
    '1..21'             => :wrong_end, # runs one past the end
    '1..19'             => :wrong_end, # stops one short — PATENT-386 has both
    '1'                 => :wrong_end,
    '5..21'             => :ambiguous, # does not start at base 1
    '10..1'             => :ambiguous,
    '<1..>21'           => :ambiguous,
    '<1..21'            => :ambiguous,
    'J00194.1:1..21'    => :ambiguous,
    'complement(1..25)' => :ambiguous,
    'join(1..4,6..25)'  => :ambiguous,
    ''                  => :missing,
    '1..E'              => :unreadable,
    'garbage!!'         => :unreadable
  }.each do |location, expected|
    test "#{location.presence || '(blank)'} over 20 bases is #{expected.inspect}" do
      actual = St26SourceLocations.disagreement(location, 20)

      expected.nil? ? assert_nil(actual) : assert_equal(expected, actual)
    end
  end

  test 'audit finds the disagreements and leaves the clean entries alone' do
    submission = seed('1..21', '1..19', '1..20')

    result = St26SourceLocations.audit

    assert_equal %w[ACC_000001 ACC_000002], result.findings.map(&:accession)
    assert_equal %i[wrong_end wrong_end], result.findings.map(&:reason)
    assert_empty result.unreadable
    assert_empty result.skipped
    assert_equal submission, result.findings.first.submission
  end

  # Both directions land on the sequence length, and nothing else moves.
  test 'correct! sets the wrong-ended locations to the full span' do
    submission = seed('1..21', '1..19', '1..20', '5..21')
    before     = record_of(submission)

    capture_io do
      St26SourceLocations.correct! St26SourceLocations.audit.findings.select(&:correctable?)
    end

    after = record_of(submission)

    assert_equal %w[1..20 1..20 1..20 5..21], locations_of(after)
    assert_equal blind_to_locations(before), blind_to_locations(after),
                 'the correction rewrote something other than a location'
  end

  # The guard used to fire in the middle of the loop, so a batch whose later
  # submission tripped it aborted with the earlier ones already rewritten.
  test 'correct! writes nothing when a finding does not line up with the record' do
    submission = seed('1..21')
    finding    = St26SourceLocations.audit.findings.first.with(source_index: 7)

    assert_raises RuntimeError do
      St26SourceLocations.correct! [finding]
    end

    assert_equal %w[1..21], locations_of(record_of(submission))
  end

  # The check is on what the location says, not just on how many index pairs
  # were hit: a record that changed shape between the audit and the rewrite
  # would otherwise be rewritten at positions now meaning something else.
  test 'correct! writes nothing when the record changed since the audit' do
    submission = seed('1..21')
    finding    = St26SourceLocations.audit.findings.first

    seed '1..25' # same position, different location

    assert_raises RuntimeError do
      St26SourceLocations.correct! [finding]
    end

    assert_equal %w[1..25], locations_of(record_of(submission))
  end

  # An entry with no sequence has no length for a location to agree with, and
  # used to be passed over silently — so the audit could call the archive clean
  # over an entry it had not examined.
  test 'an entry with no sequence is reported rather than passed over' do
    seed_entries [{'id' => 'SEQ|JP|2026123456|A|1', 'sequence' => '', 'length' => 0, 'source_features' => [{'location' => '1..20'}]}]

    result = St26SourceLocations.audit

    assert_equal %i[no_sequence], result.findings.map(&:reason)
    refute_predicate result.findings.first, :correctable?
  end

  test 'a submission with no record is skipped rather than passed over' do
    submission = seed('1..20')
    submission.ddbj_record.purge

    result = St26SourceLocations.audit

    assert_equal [submission], result.skipped.map(&:submission)
    assert_empty result.findings
  end

  test 'an unreadable record is reported instead of aborting the scan' do
    submission = seed('1..21')
    ActiveStorage::Blob.service.delete submission.ddbj_record.blob.key

    result = St26SourceLocations.audit

    assert_equal [submission], result.unreadable.map(&:submission)
    assert_empty result.findings
  end

  test 'accessions that match nothing are reported as unmatched' do
    seed '1..21'

    result = St26SourceLocations.audit('ACC_000001, NOPE_000009')

    assert_equal %w[NOPE_000009], result.unmatched
  end

  # The number the decision turns on. PATENT-386 needed it for two refused
  # rows and it was not on the line, so it had to be looked up by hand.
  test 'the report prints the sequence length on refused rows too' do
    seed 'join(1..4,6..25)'

    out, = capture_io { St26SourceLocations.report St26SourceLocations.audit }

    assert_match(/sequence=20/, out)
    assert_match(/NOT REWRITTEN \(ambiguous\)/, out)
  end

  # Naming one accession must not drag its siblings into the rewrite.
  test 'findings outside the named accessions are siblings' do
    seed '1..21', '1..31'

    result = St26SourceLocations.audit('ACC_000001')

    assert_equal %w[ACC_000001], result.named.map(&:accession)
    assert_equal %w[ACC_000002], result.siblings.map(&:accession)
  end

  private

  # One ST.26 submission whose entries carry the given source locations, using
  # the two accessions the entries fixture already names.
  def seed(*locations)
    # Every entry is twenty bases, so a location in a test reads against the
    # same length whichever entry it lands on.
    seed_entries locations.each_with_index.map {|location, i|
      sequence = 'acgt' * 5

      {
        'id'              => "SEQ|JP|2026123456|A|#{i + 1}",
        'type'            => 'other',
        'topology'        => 'linear',
        'sequence'        => sequence,
        'length'          => sequence.size,
        'tax_id'          => 9606,
        'source_features' => [{'id' => "source_#{i}", 'location' => location, 'source' => {'organism' => 'synthetic construct', 'mol_type' => 'other DNA', 'qualifiers' => {}}}]
      }
    }
  end

  def seed_entries(entries)
    submission = submissions(:st26)

    record = {
      'schema_version' => 'v2',
      'provenance'     => {'source_format' => 'ST26'},
      'submission'     => {'division' => 'PAT'},
      'sequences'      => {'entries' => entries},
      'features'       => []
    }

    submission.update!(
      ddbj_record: {
        io:           StringIO.new(Oj.dump(record, mode: :strict)),
        filename:     'record.json',
        content_type: 'application/json'
      }
    )

    submission
  end

  def record_of(submission) = submission.reload.ddbj_record.open { Oj.load(it.read, mode: :strict) }

  def locations_of(record) = record.dig('sequences', 'entries').flat_map { it['source_features'].map { it['location'] } }

  # The record with every location blanked, so an assertion can ask whether
  # anything *else* moved.
  def blind_to_locations(record)
    copy = Oj.load(Oj.dump(record, mode: :strict), mode: :strict)

    copy.dig('sequences', 'entries').each { it['source_features'].each { it['location'] = nil } }

    copy
  end
end
