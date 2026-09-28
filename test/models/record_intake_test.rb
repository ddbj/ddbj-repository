require 'test_helper'

class RecordIntakeTest < ActiveSupport::TestCase
  RECORD = {'schema_version' => 'v3', 'projects' => [{'alias' => 'p', 'title' => 'A project', 'project_type' => 'primary'}]}.freeze

  def findings(record, db: 'bioproject')
    request = SubmissionRequest.new(db:)
    request.ddbj_record.attach ActiveStorage::Blob.create_and_upload!(io: StringIO.new(record.is_a?(String) ? record : record.to_json), filename: 'record.json', content_type: 'application/json')

    RecordIntake.findings(request).map { it[:code] }
  end

  test 'a record of its own database, with no accessions, may go on' do
    assert_empty findings(RECORD)
    assert_empty findings({'schema_version' => 'v3.1', 'samples' => [{'alias' => 's'}]}, db: 'biosample')
  end

  test 'what is not JSON, or not v3, is refused' do
    assert_equal %w[TRD_R0013], findings('{"schema_version": ')
    assert_equal %w[TRD_R0017], findings(RECORD.merge('schema_version' => 'v2'))
    assert_equal %w[TRD_R0017], findings('[]')
  end

  test 'a request is for one database' do
    assert_equal %w[TRD_R0018], findings(RECORD.merge('samples' => []))
    assert_equal %w[TRD_R0018], findings({'schema_version' => 'v3', 'projects' => [], 'samples' => []}, db: 'biosample')
  end

  test 'accessions are issued here, not brought' do
    record = RECORD.merge('projects' => [RECORD['projects'][0].merge('accession' => 'PRJDB1')])

    assert_equal %w[TRD_R0019], findings(record)
  end

  test 'a record that cannot be kept in its canonical form is refused' do
    record = RECORD.merge('projects' => [RECORD['projects'][0].merge('title' => "bell\u0007")])

    assert_equal %w[TRD_R0020], findings(record)
  end
end
