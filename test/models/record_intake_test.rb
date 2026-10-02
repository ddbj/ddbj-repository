require 'test_helper'

class RecordIntakeTest < ActiveSupport::TestCase
  RECORD = {'schema_version' => 'v3', 'projects' => [{'alias' => 'p', 'title' => 'A project', 'project_type' => 'primary'}]}.freeze

  def findings(record, db: 'bioproject')
    request = SubmissionRequest.new(db:, user: users(:alice))
    request.ddbj_record.attach ActiveStorage::Blob.create_and_upload!(io: StringIO.new(record.is_a?(String) ? record : record.to_json), filename: 'record.json', content_type: 'application/json')

    RecordIntake.findings(request)
  end

  def codes(record, **) = findings(record, **).map { it[:code] }

  test 'a record of its own database, with no accessions, may go on' do
    assert_empty codes(RECORD)
    assert_empty codes({'schema_version' => 'v3', 'samples' => [{'alias' => 's'}]}, db: 'biosample')
  end

  # docs/v3-schema.md: one record may carry several databases, the
  # accession of the one registered first written in before the next.
  test 'a record may carry the other database, accessions and all' do
    record = RECORD.merge('projects' => [RECORD['projects'][0].merge('accession' => 'PRJDB1')], 'samples' => [{'alias' => 's'}])

    assert_empty codes(record, db: 'biosample')
  end

  test 'what is not JSON, not UTF-8, nested past reading, or not v3 is refused' do
    assert_equal %w[TRD_R0013], codes('{"schema_version": ')
    assert_match(/line \d+, column \d+/, findings('{"schema_version": ').sole[:message])
    assert_equal %w[TRD_R0013], codes("{\"schema_version\": \"v3\", \"projects\": [{\"alias\": \"\xFF\"}]}")
    assert_equal %w[TRD_R0013], codes("{\"schema_version\": \"v3\", \"projects\": #{'[' * 100_000}#{']' * 100_000}}")
    assert_equal %w[TRD_R0017], codes(RECORD.merge('schema_version' => 'v2'))
    assert_equal %w[TRD_R0017], codes('[]')
  end

  test 'accessions of its own objects are issued here, not brought' do
    record = RECORD.merge('projects' => [RECORD['projects'][0].merge('accession' => 'PRJDB1')])

    assert_equal %w[TRD_R0018], codes(record)
    assert_equal 'p', findings(record).sole[:entry_id]
  end

  test 'a record that cannot be kept in its canonical form is refused' do
    record = RECORD.merge('projects' => [RECORD['projects'][0].merge('title' => "bell\u0007")])

    assert_equal %w[TRD_R0019], codes(record)
  end

  # A sample is kept, found and issued its accession by its alias, as it
  # is kept — whitespace collapsed.
  test 'samples each need an alias of their own, and there must be something to register' do
    assert_equal %w[TRD_R0020], codes({'schema_version' => 'v3', 'samples' => [{'alias' => 's'}]})
    assert_equal %w[TRD_R0020], codes({'schema_version' => 'v3', 'samples' => []}, db: 'biosample')
    assert_equal %w[TRD_R0020 TRD_R0020], codes({'schema_version' => 'v3', 'samples' => [{'title' => 'x'}, {'alias' => ' '}]}, db: 'biosample')

    repeated = findings({'schema_version' => 'v3', 'samples' => [{'alias' => 'a b'}, {'alias' => 'a  b'}, {'alias' => 'c'}]}, db: 'biosample')

    assert_equal [['TRD_R0020', 'a b']], repeated.map { it.values_at(:code, :entry_id) }
  end

  # Read whole in the process that serves the API; a record too large for
  # that is refused before it is downloaded.
  test 'a record too large to read here is refused unread' do
    request = SubmissionRequest.new(db: 'biosample')
    request.ddbj_record.attach ActiveStorage::Blob.create_and_upload!(io: StringIO.new(RECORD.to_json), filename: 'record.json', content_type: 'application/json')
    request.ddbj_record.blob.update_columns(byte_size: RecordIntake::MAX_BYTES + 1)

    request.ddbj_record.blob.stub(:download, -> { flunk 'read before its size was asked' }) do
      assert_equal %w[TRD_R0021], RecordIntake.findings(request).map { it[:code] }
    end
  end

  # --- DRA ---------------------------------------------------------------

  READS = "@r1\nACGT\n+\nIIII\n"

  def upload(name, body = READS, user: users(:alice))
    user.unassigned_files.attach(io: StringIO.new(body), filename: name, content_type: 'application/octet-stream')
  end

  def dra_record(files)
    {
      'schema_version' => 'v3',
      'experiments'    => [{'alias' => 'exp1'}],
      'runs'           => [{'alias' => 'run1', 'data_blocks' => [{'files' => files}]}]
    }
  end

  def fastq(name, md5 = Digest::MD5.hexdigest(READS)) = {'filename' => name, 'filetype' => 'fastq', 'checksum_method' => 'MD5', 'checksum' => md5}

  test 'a DRA record needs objects of its own, and brings no accessions for them' do
    assert_equal %w[TRD_R0020], codes({'schema_version' => 'v3', 'samples' => [{'alias' => 's'}]}, db: 'dra')
    assert_match 'experiments, runs, or analyses', findings({'schema_version' => 'v3'}, db: 'dra').sole[:message]

    assert_equal %w[TRD_R0018], codes({'schema_version' => 'v3', 'runs' => [{'alias' => 'r', 'accession' => 'DRR000001'}]}, db: 'dra')
  end

  # The reads go up first; the record names them, and its MD5 says which.
  test 'the files a DRA record names are its submitter\'s uploads, with the MD5 it states' do
    upload 'r_1.fastq'

    assert_empty codes(dra_record([fastq('r_1.fastq')]), db: 'dra')

    missing   = findings(dra_record([fastq('r_2.fastq')]), db: 'dra').sole
    different = findings(dra_record([fastq('r_1.fastq', 'f' * 32)]), db: 'dra').sole
    unstated  = findings(dra_record([fastq('r_1.fastq').except('checksum')]), db: 'dra').sole

    assert_equal ['TRD_R0022', 'run1'], missing.values_at(:code, :entry_id)
    assert_match 'runs[0] r_2.fastq has not been uploaded', missing[:message]
    assert_match 'its MD5 is not ffff', different[:message]
    assert_match 'states no MD5', unstated[:message]
  end

  # Somebody else's upload of the same file is not this submitter's.
  test 'another account\'s upload of the file does not count' do
    upload 'r_1.fastq', user: users(:carol)

    assert_equal %w[TRD_R0022], codes(dra_record([fastq('r_1.fastq')]), db: 'dra')
  end
end
