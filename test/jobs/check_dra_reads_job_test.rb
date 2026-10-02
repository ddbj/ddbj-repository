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

  test 'a run without files, or with a file of no filetype, fails without reading' do
    validation = held(record.merge('runs' => [{'alias' => 'run1'}]))

    assert_empty read(validation) { flunk 'read' }
    assert_match 'runs[0] names no files', validation.details.find_by!(code: 'TRD_R0023').message

    @request.validation.destroy
    validation = held(record([fastq('r_1.fastq').except('filetype')]))

    assert_empty read(validation) { flunk 'read' }
    assert_match 'states no filetype', validation.details.find_by!(code: 'TRD_R0023').message
  end

  # Each run on its own, in the record's order.
  test 'every run is read, with its own files' do
    two = record([fastq('r_1.fastq')]).tap {
      it['runs'] << {'alias' => 'run2', 'data_blocks' => [{'files' => [fastq('r_2.fastq')]}]}
    }

    calls = read(held(two), ok)

    assert_equal [%w[r_1.fastq], %w[r_2.fastq]], calls.map { it[:files].map { it.filename.to_s } }
  end

  # A run's own platform first; else its experiment's, named as the
  # converter names it — by accession, or by alias and position among
  # namesakes.
  test 'the platform is the run\'s own, or its experiment\'s however the relation names it' do
    own = record.tap { it['runs'][0]['platform'] = {'type' => 'ILLUMINA'} }

    assert_equal 'ILLUMINA', read(held(own), ok).sole[:platform]

    by_accession = record.tap {
      it['experiments'] = [{'alias' => 'x', 'accession' => 'DRX000001', 'platform' => {'type' => 'ION_TORRENT'}}]
      it['relations'][0]['target'] = {'db' => 'experiment', 'accession' => 'DRX000001'}
    }

    @request.validation.destroy
    assert_equal 'ION_TORRENT', read(held(by_accession), ok).sole[:platform]

    namesakes = record([fastq('r_1.fastq')]).tap {
      it['runs'] << {'alias' => 'run1', 'data_blocks' => [{'files' => [fastq('r_2.fastq')]}]}
      it['experiments'] << {'alias' => 'exp1', 'platform' => {'type' => 'LS454'}}
      it['relations'] = [
        {'type' => 'part_of', 'source' => {'type' => 'run', 'alias' => 'run1', 'index' => 0}, 'target' => {'db' => 'experiment', 'id' => 'exp1', 'index' => 0}},
        {'type' => 'part_of', 'source' => {'type' => 'run', 'alias' => 'run1', 'index' => 1}, 'target' => {'db' => 'experiment', 'id' => 'exp1', 'index' => 1}}
      ]
    }

    @request.validation.destroy
    assert_equal %w[ABI_SOLID LS454], read(held(namesakes), ok).map { it[:platform] }
  end

  test 'a reading past its time, or failing for any other reason, ends the check as not carried out' do
    [DRA::ReadCheck::TimedOut.new('latf-load had not finished within 12 hours'), Aws::S3::Errors::ServiceError.new(nil, 'down')].each do |error|
      @request.validation&.destroy
      validation = held

      read(validation) { raise error }

      assert CurationState.new(@request.reload).unchecked?, error.class.name
      assert validation.reload.finished?
    end
  end

  # The validator's report was written when the check was held.
  test 'concluding after the reads keeps the validator\'s report' do
    validation = held

    read validation, ok

    assert_equal({'validity' => true, 'messages' => []}, validation.reload.raw_result)
  end

  # A deploy gives the job under a minute; a run takes hours. Taken up again,
  # it reads only the run it was stopped in, and the findings of those before
  # are there once.
  test 'a reading stopped part way is taken up again at the run it was in' do
    two = record([fastq('r_1.fastq')]).tap {
      it['runs'] << {'alias' => 'run2', 'data_blocks' => [{'files' => [fastq('r_2.fastq')]}]}
    }

    validation = held(two)
    read       = []
    stopped    = false

    check = lambda {|files:, dir:, interrupt:, **|
      read << files.map { it.filename.to_s }
      dir.mkpath

      if files.first.filename.to_s == 'r_2.fastq' && !stopped
        stopped = true
        raise ActiveJob::Continuation::Interrupt, 'stopping'
      end

      ok("latf-load err: one bad record in #{files.first.filename}\n")
    }

    DRA::ReadCheck.stub(:call, check) do
      CheckDRAReadsJob.perform_now validation

      assert validation.reload.running?, 'stopped, not concluded'
      assert CheckDRAReadsJob.kept_dir(validation.id).join('run-1').exist?, 'copies kept for the next attempt'
      assert_not CheckDRAReadsJob.kept_dir(validation.id).join('run-0').exist?, 'a run read is a run done with'

      perform_enqueued_jobs only: CheckDRAReadsJob
    end

    assert_equal [%w[r_1.fastq], %w[r_2.fastq], %w[r_2.fastq]], read
    assert_equal 2, validation.reload.details.where(code: 'TRD_R0024').count, 'one finding a run'
    assert @request.reload.ready_to_apply?
    assert_not CheckDRAReadsJob.kept_dir(validation.id).exist?, 'removed once concluded'
  end

  # What Solid Queue does on a deploy: says it is stopping, and the job,
  # looking in from the tool it is running, stops and is taken up again —
  # ahead of the readings that have not started.
  test 'a stopping worker interrupts the reading through the tool, and it is taken up again first' do
    validation = held
    check      = lambda {|interrupt:, **|
      interrupt.()
      ok
    }

    CheckDRAReadsJob.queue_adapter.stub(:stopping?, true) do
      DRA::ReadCheck.stub(:call, check) { CheckDRAReadsJob.perform_now validation }
    end

    assert validation.reload.running?
    assert_enqueued_with job: CheckDRAReadsJob, priority: 0
  end

  test 'copies kept for a check no longer running are discarded, a running one\'s kept' do
    running = held
    ended   = submission_requests(:st26).validation.tap { it.update!(progress: :finished, finished_at: Time.current) }

    [running, ended].each { CheckDRAReadsJob.kept_dir(it.id).join('run-0').mkpath }
    CheckDRAReadsJob.kept_dir('gone').mkpath

    CheckDRAReadsJob.discard_abandoned_copies

    assert CheckDRAReadsJob.kept_dir(running.id).exist?
    assert_not CheckDRAReadsJob.kept_dir(ended.id).exist?
    assert_not CheckDRAReadsJob.kept_dir('gone').exist?
  ensure
    CheckDRAReadsJob.kept_dir(running.id).rmtree if running
  end
end
