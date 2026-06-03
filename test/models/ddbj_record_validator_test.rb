require 'test_helper'

class DDBJRecordValidatorTest < ActiveSupport::TestCase
  # Minimal valid v2 record carrying a single entry. The sequence and its
  # mol_type are injected by the caller so each test can exercise a specific
  # shape (nucleotide vs protein).
  def attach_record(request, sequence, mol_type: 'genomic DNA')
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
            length:   sequence.length,
            tax_id:   9606,

            source_features: [
              {
                id:       'source_1',
                location: "1..#{sequence.length}",

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

      features: []
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

  # Smoke tests pinning the v2 vs v3 routing. Both fixtures are valid
  # enough to flow through end-to-end — no TRD_R9999 catch-all should
  # fire.

  test 'v2 fixture validates without error (smoke)' do
    request = build_request(file_fixture('ddbj_record/example.json'))

    DDBJRecordValidator.validate request

    refute request.reload.validation_failed?
    refute request.validation.details.exists?(code: 'TRD_R9999'),
           "TRD_R9999 indicates the validator caught an exception: #{request.validation.details.where(code: 'TRD_R9999').first&.message}"
  end

  test 'v3 fixture validates without raising (Phase 6 v3 port smoke)' do
    request = build_request(file_fixture('ddbj_record/v3_trad_gnm.json'))

    DDBJRecordValidator.validate request

    # Critical: NO TRD_R9999 (catch-all) — the v3 path navigates
    # submission.st26 / entry.alias / etc. cleanly without
    # NoMethodError.
    refute request.validation.details.exists?(code: 'TRD_R9999'),
           "v3 path produced TRD_R9999 (validator crashed): #{request.validation.details.where(code: 'TRD_R9999').first&.message}"
  end

  private

  def validate_sequence(sequence, mol_type: 'genomic DNA')
    request = submission_requests(:st26)
    request.ddbj_record.purge if request.ddbj_record.attached?
    attach_record(request, sequence, mol_type:)
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
end
