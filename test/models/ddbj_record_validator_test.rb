require 'test_helper'

class DDBJRecordValidatorTest < ActiveSupport::TestCase
  # Minimal valid v2 record carrying a single entry. The sequence and its
  # mol_type are injected by the caller so each test can exercise a specific
  # shape (nucleotide vs protein).
  def attach_record(request, sequence, mol_type: 'genomic DNA', location: nil, length: :measured, features: [])
    record = {
      schema_version: 'v2',
      provenance:     {source_format: 'ST26'},

      submission: {
        submitters:                                   [],
        db_xrefs:                                     [],
        references:                                   [],
        comments:                                     [],
        division:                                     'PAT',
        earliest_priority_application_identifications: [],

        application_identification: {
          application_number_text: '2026-123456',
          filing_date:             '2026-01-15',
          ip_office_code:          'JP'
        }
      },

      experiments: [],

      sequences: {
        common_source: {organism: '', mol_type: '', qualifiers: {}},

        entries: [
          {
            id:       'SEQ|JP|2026123456|A|1',
            type:     'other',
            topology: 'linear',
            sequence:,
            length:   (length == :measured ? sequence.length : length),
            tax_id:   9606,

            source_features: [
              {
                id:       'source_1',
                location: location || "1..#{sequence.length}",

                source: {
                  organism:   'Homo sapiens',
                  mol_type:,
                  qualifiers: {}
                }
              }
            ]
          }
        ]
      },

      features:
    }

    request.ddbj_record.attach(
      io:           StringIO.new(Oj.dump(record, mode: :rails)),
      filename:     'record.json',
      content_type: 'application/json'
    )
  end

  def codes(request)
    request.validation.details.pluck(:code)
  end

  # Regression guard: a large but valid nucleotide sequence must not be
  # misclassified as an error, and must never surface as TRD_R9999. The
  # sequence checks used to run a case-insensitive regexp over the whole
  # sequence, which blows past Regexp.timeout on multi-MB inputs. We pin an
  # aggressive timeout so a revert to the regexp form fails here rather than
  # only on production-sized (80M+ char) sequences.
  test 'large valid nucleotide sequence does not trip Regexp.timeout' do
    request = submission_requests(:st26)
    attach_record request, 'acgt' * 8_000_000 # 32 MB, valid

    with_regexp_timeout 0.05 do
      DDBJRecordValidator.validate request
    end

    refute_includes codes(request), 'TRD_R9999',
                    'valid sequence produced a regexp match timeout'
    assert_predicate request.reload, :ready_to_apply?
  end

  test 'nucleotide sequence character checks classify correctly without regexp' do
    with_regexp_timeout 0.05 do
      assert_includes validate_sequence('n' * 100), 'TRD_R0003'   # N-only
      assert_includes validate_sequence('acgtx'),   'TRD_R0005'   # invalid char
      refute_includes validate_sequence('acgtn'),   'TRD_R0003'   # mixed, not N-only
      refute_includes validate_sequence('acgtn'),   'TRD_R0005'   # all IUPAC
    end
  end

  test 'protein X-only check classifies correctly without regexp' do
    with_regexp_timeout 0.05 do
      assert_includes validate_sequence('x' * 100, mol_type: 'protein'), 'TRD_R0004' # X-only
      refute_includes validate_sequence('mkvx',    mol_type: 'protein'), 'TRD_R0004' # mixed, not X-only
    end
  end

  # INSDC-3468 / PATENT-386: JPO ST.26 files carried source locations that
  # overran the sequence (1..21 over 20 bases), and the flatfile printed the
  # disagreement twice — the source location and the REFERENCE span. Refused
  # rather than corrected, so the producer fixes the file.
  test 'source location that overruns the sequence is refused' do
    assert_includes validate_sequence('acgtacgtac', location: '1..11'), 'TRD_R0013'
  end

  test 'source location shorter than the sequence is refused' do
    assert_includes validate_sequence('acgtacgtac', location: '1..9'), 'TRD_R0013'
  end

  test 'source location matching the sequence passes' do
    refute_includes validate_sequence('acgtacgtac', location: '1..10'), 'TRD_R0013'
  end

  # Notation, not length: a single base may be written either way, and the
  # span is what the flatfile prints.
  test 'bare position on a single-base sequence passes' do
    refute_includes validate_sequence('a', location: '1'), 'TRD_R0013'
  end

  test 'split location covering the whole sequence passes' do
    refute_includes validate_sequence('acgtacgtac', location: 'join(1..4,5..10)'), 'TRD_R0013'
  end

  test 'unreadable source location is refused rather than raised' do
    codes = validate_sequence('acgtacgtac', location: 'garbage!!')

    assert_includes codes, 'TRD_R0013'
    refute_includes codes, 'TRD_R9999', 'a bad location must not surface as the catch-all'
  end

  # `1..E` is the MSS end-of-sequence form. Flatfile::Entry#location_span
  # raises on it, so such a record cannot be rendered today and fails at
  # apply as the catch-all — refusing it here is where the submitter can
  # read it. Trad migration will have to teach both ends about it.
  test 'MSS end-of-sequence location is refused for now' do
    assert_includes validate_sequence('acgtacgtac', location: '1..E'), 'TRD_R0013'
  end

  test 'source feature with no location is refused' do
    request = submission_requests(:st26)
    attach_record request, 'acgtacgtac', location: ''

    DDBJRecordValidator.validate request

    assert_includes codes(request), 'TRD_R0013'
    assert_match 'no location', request.validation.details.find_by(code: 'TRD_R0013').message
  end

  # The length attribute is what LOCUS prints, so a length that disagrees
  # with the sequence ships the same defect one step earlier — and a
  # location measured against it would look correct all the way through.
  test 'declared length that disagrees with the sequence is refused' do
    request = submission_requests(:st26)
    attach_record request, 'acgtacgtac', length: 11, location: '1..11'

    DDBJRecordValidator.validate request

    detail = request.validation.details.find_by(code: 'TRD_R0013')

    assert_match 'declared length 11', detail.message
    assert_equal 1, request.validation.details.where(code: 'TRD_R0013').count,
                 'the location is not reported separately when the length it would be measured against is itself wrong'
  end

  # `length` is a v2 server extension and older records omit it. Falling back
  # to the sequence keeps the check running rather than silently disabling it.
  test 'missing declared length falls back to measuring the sequence' do
    assert_includes validate_sequence('acgtacgtac', length: nil, location: '1..11'), 'TRD_R0013'
    refute_includes validate_sequence('acgtacgtac', length: nil, location: '1..10'), 'TRD_R0013'
  end

  # A JSON string where a number belongs used to make every comparison fail
  # and print `spans 1..10 but the sequence is 10 long`.
  test 'declared length carried as a string is read as a number' do
    refute_includes validate_sequence('acgtacgtac', length: '10', location: '1..10'), 'TRD_R0013'
  end

  # The full-length rule is the patent one. Several sources dividing one entry
  # is what the v2 schema's own comment on SourceFeature describes, and a
  # genome record built that way must not be refused — only a location that
  # leaves the sequence is wrong everywhere.
  test 'partial source location is accepted outside the patent database' do
    request = SubmissionRequest.new(user: users(:alice), db: 'biosample')
    attach_record request, 'acgtacgtac', location: '1..5'
    request.save!

    DDBJRecordValidator.validate request

    refute_includes codes(request), 'TRD_R0013'
  end

  test 'source location leaving the sequence is refused outside the patent database too' do
    request = SubmissionRequest.new(user: users(:alice), db: 'biosample')
    attach_record request, 'acgtacgtac', location: '1..11'
    request.save!

    DDBJRecordValidator.validate request

    assert_includes codes(request), 'TRD_R0013'
  end

  # `Bio::Locations#span` is not normalised — `10..1` comes back as [10, 1] —
  # so the bound checks passed it while the REFERENCE line would render
  # "bases 10 to 1".
  test 'backwards source location is refused' do
    codes = validate_sequence('acgtacgtac', location: '10..1')

    assert_includes codes, 'TRD_R0013'
    refute_includes codes, 'TRD_R9999'
  end

  test 'backwards location is refused outside the patent database too' do
    request = SubmissionRequest.new(user: users(:alice), db: 'biosample')
    attach_record request, 'acgtacgtac', location: '10..1'
    request.save!

    DDBJRecordValidator.validate request

    assert_includes codes(request), 'TRD_R0013'
  end

  # An ordinary feature's location ships in the flatfile the same way a
  # source's does, so one that leaves the sequence carries the same defect.
  # Never full-length though: covering part of the entry is what features are
  # for.
  test 'feature location leaving the sequence is refused' do
    request = submission_requests(:st26)
    attach_record request, 'acgtacgtac', features: [{type: 'CDS', location: '1..11', sequence_id: 'SEQ|JP|2026123456|A|1', qualifiers: {}}]

    DDBJRecordValidator.validate request

    detail = request.validation.details.find_by(code: 'TRD_R0013')

    assert_match 'feature=CDS', detail.message
  end

  test 'feature location inside the sequence passes' do
    request = submission_requests(:st26)
    attach_record request, 'acgtacgtac', features: [{type: 'CDS', location: '2..5', sequence_id: 'SEQ|JP|2026123456|A|1', qualifiers: {}}]

    DDBJRecordValidator.validate request

    refute_includes codes(request), 'TRD_R0013'
  end

  # Nothing to measure against, and a feature naming an entry that is not
  # there is a different complaint than this code makes.
  test 'feature naming an unknown sequence is not measured' do
    request = submission_requests(:st26)
    attach_record request, 'acgtacgtac', features: [{type: 'CDS', location: '1..999', sequence_id: 'nonexistent', qualifiers: {}}]

    DDBJRecordValidator.validate request

    refute_includes codes(request), 'TRD_R0013'
  end

  # v3 makes SourceFeature#location optional, so a v3 record that omits it is
  # schema-legal and must not be refused. v2 requires it.
  test 'v3 source feature without a location is accepted' do
    json = {
      'schema_version' => 'v3',

      'sequences' => {
        'common_source' => {'mol_type' => 'genomic DNA'},
        'entries'       => [{'alias' => 'chr1', 'sequence' => 'acgtacgtac', 'source_features' => [{}]}]
      }
    }.to_json

    request = build_request_from_json(json)

    DDBJRecordValidator.validate request

    refute_includes codes(request), 'TRD_R0013'
  end

  # The following tests pin the v2 vs v3 routing plus several specific
  # failure modes the code review surfaced. The smoke fixtures are valid
  # enough to flow through end-to-end — no TRD_R9999 catch-all should fire.

  test 'v2 fixture validates without error (smoke)' do
    request = build_request(file_fixture('ddbj_record/example.json'))

    DDBJRecordValidator.validate request

    refute request.reload.validation_failed?
    refute request.validation.details.exists?(code: 'TRD_R9999'),
           "TRD_R9999 indicates the validator caught an exception: #{request.validation.details.where(code: 'TRD_R9999').first&.message}"
  end

  test 'v3 fixture: mol_type hoisted to common_source suppresses TRD_R0010 false-positive' do
    request = build_request(file_fixture('ddbj_record/v3_trad_gnm.json'))

    DDBJRecordValidator.validate request

    refute request.validation.details.exists?(code: 'TRD_R9999'),
           "v3 path produced TRD_R9999: #{request.validation.details.where(code: 'TRD_R9999').first&.message}"
    refute request.validation.details.exists?(code: 'TRD_R0010'),
           'v3 fixture has common_source.mol_type set; TRD_R0010 is a false positive'
    # (TRD_R0005 and TRD_R0013 fire legitimately because the vendored
    # fixture uses a `...(N bp)...` placeholder string in the sequence
    # field — so the characters are invalid and the sequence is far
    # shorter than the source location claims. A fixture quality issue,
    # not a validator bug.)
  end

  test 'v2 record missing sequences block still fails loudly via TRD_R9999 (regression guard)' do
    # The v3 port wraps record.sequences&.entries in Array() — a v2
    # record with a missing `sequences` key must still surface as an
    # error rather than silently ready_to_apply.
    request = build_request_from_json('{"submission":{"comments":["no sequences here"]}}')

    DDBJRecordValidator.validate request

    assert request.reload.validation_failed?
    assert request.validation.details.exists?(code: 'TRD_R9999'),
           'v2 record missing sequences block should produce TRD_R9999, not silently pass'
  end

  test 'v3 record with bare nullable feature.qualifiers does not crash' do
    json = {
      'schema_version' => 'v3',
      'features'       => [{'type' => 'gap', 'location' => '100..200', 'sequence_id' => 'chromosome'}]
    }.to_json
    request = build_request_from_json(json)

    DDBJRecordValidator.validate request

    refute request.validation.details.exists?(code: 'TRD_R9999'),
           'nil feature.qualifiers must be handled gracefully, not crash'
  end

  private

  def validate_sequence(sequence, mol_type: 'genomic DNA', location: nil, length: :measured)
    request = submission_requests(:st26)
    request.ddbj_record.purge if request.ddbj_record.attached?
    attach_record(request, sequence, mol_type:, location:, length:)
    DDBJRecordValidator.validate request
    codes request
  end

  def with_regexp_timeout(seconds)
    original       = Regexp.timeout
    Regexp.timeout = seconds
    yield
  ensure
    Regexp.timeout = original
  end

  def build_request(fixture_path)
    request = SubmissionRequest.new(user: users(:alice), db: 'st26')
    request.ddbj_record.attach(io: File.open(fixture_path), filename: fixture_path.basename.to_s, content_type: 'application/json')
    request.save!
    request
  end

  def build_request_from_json(json)
    request = SubmissionRequest.new(user: users(:alice), db: 'st26')
    request.ddbj_record.attach(io: StringIO.new(json), filename: 'inline.json', content_type: 'application/json')
    request.save!
    request
  end
end
