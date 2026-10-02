require 'test_helper'

class CheckDRAReadsJobTest < ActiveJob::TestCase
  READS = "@r1\nACGT\n+\nIIII\n"

  setup do
    @user    = users(:alice)
    @request = SubmissionRequest.new(user: @user, db: 'dra', status: :validating).tap { it.save!(validate: false) }

    @user.unassigned_files.attach(io: StringIO.new(READS), filename: 'r_1.fastq', content_type: 'application/octet-stream')
    @user.unassigned_files.attach(io: StringIO.new(READS), filename: 'r_2.fastq', content_type: 'application/octet-stream')
  end

  def fastq(name, filetype: 'fastq') = {'filename' => name, 'filetype' => filetype, 'checksum_method' => 'MD5', 'checksum' => Digest::MD5.hexdigest(READS)}

  def record(files = [fastq('r_1.fastq'), fastq('r_2.fastq')])
    {
      'schema_version' => 'v3',
      'experiments'    => [{'alias' => 'exp1', 'platform' => {'type' => 'ABI_SOLID'}}],
      'runs'           => [{'alias' => 'run1', 'data_blocks' => [{'files' => files}]}],
      'relations'      => [{'type' => 'part_of', 'source' => {'type' => 'run', 'alias' => 'run1'}, 'target' => {'db' => 'experiment', 'id' => 'exp1'}}]
    }
  end

  # As DDBJValidatorCheck.hold leaves it: the validator's findings written,
  # still running.
  def held(record = self.record)
    @request.ddbj_record.attach(io: StringIO.new(record.to_json), filename: 'dra.json', content_type: 'application/json')

    @request.create_validation!(progress: :running, raw_result: {'validity' => true, 'messages' => []}).tap {
      it.details.create!(code: 'DRA_R0099', severity: :warning, message: 'From the validator.')
    }
  end

  def read(validation, result = nil, &)
    calls = []
    check = lambda {|**kwargs|
      calls << kwargs
      block_given? ? yield : result
    }

    DRA::ReadCheck.stub(:call, check) { CheckDRAReadsJob.perform_now validation }

    calls
  end

  def details(validation) = validation.reload.details.order(:id).pluck(:code, :severity)

  def ok(output = '') = DRA::ReadCheck::Result.new(ok: true, output:)

  test 'reads that read conclude the check ready to apply, the validator\'s findings kept' do
    validation = held
    calls      = read(validation, ok)

    assert validation.reload.finished?
    assert @request.reload.ready_to_apply?
    assert_equal [%w[DRA_R0099 warning]], details(validation)

    call = calls.sole

    assert_equal %w[r_1.fastq r_2.fastq], call[:files].map { it.filename.to_s }, 'the run\'s files, in the record\'s order'
    assert_equal 'fastq', call[:filetype]
    assert_equal 'ABI_SOLID', call[:platform], 'the platform of the experiment the run is part of'
  end

  test 'reads the loader refuses fail the check, with what it said' do
    validation = held

    read validation, DRA::ReadCheck::Result.new(ok: false, output: "latf-load err: length of original quality does not match sequence\n")

    assert @request.reload.validation_failed?
    assert_equal ['TRD_R0023', 'error', 'run1'], validation.details.find_by!(code: 'TRD_R0023').then { [it.code, it.severity, it.entry_id] }
    assert_match 'length of original quality', validation.details.find_by!(code: 'TRD_R0023').message
  end

  # Taken, as D-way took it — but the submitter should know.
  test 'reads read with records dropped pass, with a warning' do
    validation = held

    read validation, ok("latf-load err: one bad record\n")

    assert @request.reload.ready_to_apply?
    assert_includes details(validation), %w[TRD_R0024 warning]
  end

  test 'a run mixing filetypes, or of one not read here yet, is said so without reading' do
    validation = held(record([fastq('r_1.fastq'), fastq('r_2.fastq', filetype: 'sra')]))

    assert_empty read(validation) { flunk 'read' }
    assert_includes details(validation), %w[TRD_R0023 error]

    @request.validation.destroy
    validation = held(record([fastq('r_1.fastq', filetype: 'bam')]))

    assert_empty read(validation) { flunk 'read' }
    assert_includes details(validation), %w[TRD_R0024 warning]
    assert @request.reload.ready_to_apply?
  end

  # Taken out of the unassigned files since the record was taken in.
  test 'a file no longer among the uploads fails the check' do
    validation = held

    @user.unassigned_files.find { it.filename.to_s == 'r_2.fastq' }.purge

    assert_empty read(validation) { flunk 'read' }
    assert_includes details(validation), %w[TRD_R0022 error]
  end

  test 'a host that cannot read reads ends the check as not carried out' do
    validation = held

    read(validation) { raise DRA::ReadCheck::ToolMissing, 'latf-load is not installed here (SRA Toolkit)' }

    assert CurationState.new(@request.reload).unchecked?
  end

  # Checking again replaced it.
  test 'a check no longer running is left alone' do
    validation = held
    validation.update!(progress: :finished, finished_at: Time.current)

    assert_empty read(validation) { flunk 'read' }
  end
end
