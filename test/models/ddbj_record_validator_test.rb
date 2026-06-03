require 'test_helper'

class DDBJRecordValidatorTest < ActiveSupport::TestCase
  # The validator has zero pre-existing tests; these cases pin the v2
  # vs v3 routing added in this iteration. Both fixtures are valid
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

  def build_request(fixture_path)
    request = SubmissionRequest.new(user: users(:alice), db: 'st26')
    request.ddbj_record.attach(io: File.open(fixture_path), filename: fixture_path.basename.to_s, content_type: 'application/json')
    request.save!
    request
  end
end
