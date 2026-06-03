require 'test_helper'

class DDBJRecordValidatorTest < ActiveSupport::TestCase
  # The validator had zero pre-existing tests; this file pins the v2
  # vs v3 routing plus several specific failure modes the code-review
  # surfaced.

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
    # (TRD_R0005 fires legitimately because the vendored fixture uses
    # a `...(N bp)...` placeholder string in the sequence field — that
    # is a fixture quality issue, not a validator bug.)
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
