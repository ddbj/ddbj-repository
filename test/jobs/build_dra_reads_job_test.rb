require 'test_helper'

class BuildDRAReadsJobTest < ActiveJob::TestCase
  READS = "@r1\nACGT\n+\nIIII\n"

  setup do
    @submission = Submission.create!(db: 'dra', user: users(:alice))
    @row        = DRASubmission.create!(submission: @submission, accession: 'DRA000002', status: :accession_issued)

    %w[r_1.fastq r_2.fastq].each do |filename|
      @submission.data_files_attachments.create! blob: ActiveStorage::Blob.create_and_upload!(io: StringIO.new(READS), filename:, content_type: 'application/octet-stream')
    end
    @submission.append_update! record, actor: 'test'

    @tree = DRA::ReadsTree.at(:private)
  end

  teardown do
    @tree.root.rmtree if @tree.root.exist?
    BuildDRAReadsJob.kept_dir(@submission.id).rmtree
  end

  def fastq(name) = {'filename' => name, 'filetype' => 'fastq', 'checksum_method' => 'MD5', 'checksum' => Digest::MD5.hexdigest(READS)}

  def record(files = [fastq('r_1.fastq'), fastq('r_2.fastq')])
    {
      'schema_version' => 'v3',
      'submission'     => {'alias' => 'sub', 'accession' => 'DRA000002'},
      'experiments'    => [{'alias' => 'exp1', 'accession' => 'DRX000002', 'platform' => {'type' => 'ILLUMINA'}}],
      'runs'           => [{'alias' => 'run1', 'accession' => 'DRR000002', 'data_blocks' => [{'files' => files}]}],
      'relations'      => [{'type' => 'part_of', 'source' => {'type' => 'run', 'alias' => 'run1'}, 'target' => {'db' => 'experiment', 'id' => 'exp1'}}]
    }
  end

  # What DRA::ReadBuild would make, without SRA Toolkit.
  def built(**kwargs)
    dir = kwargs.fetch(:dir).join('built').tap(&:mkpath)
    acc = kwargs.fetch(:accession)

    DRA::ReadBuild::Result.new(
      ok:     true,
      output: '',
      sra:    dir.join("#{acc}.sra").tap { it.write('sra') },
      fastqs: %w[_1 _2].map { dir.join("#{acc}#{it}.fastq.bz2").tap { it.write('bz2') } }
    )
  end

  def perform(build = method(:built))
    calls = []

    DRA::ReadBuild.stub(:call, ->(**kwargs) { calls << kwargs; build.(**kwargs) }) do
      BuildDRAReadsJob.perform_now @submission
    end

    calls
  end

  test 'each run is built into the private tree as on the FTP site, and the submission is private' do
    calls = perform

    assert_equal [['DRR000002', 'fastq', 'ILLUMINA', %w[r_1.fastq r_2.fastq]]], calls.map { [it[:accession], it[:filetype], it[:platform], it[:files].map { it.filename.to_s }] }

    assert_equal 'sra', @tree.sra(experiment: 'DRX000002', run: 'DRR000002').read
    assert_equal %w[DRR000002_1.fastq.bz2 DRR000002_2.fastq.bz2], @tree.fastqs(submission: 'DRA000002', experiment: 'DRX000002', run: 'DRR000002').map { it.basename.to_s }
    assert @tree.root.join('sra/ByExp/sra/DRX/DRX000/DRX000002/DRR000002/DRR000002.sra').exist?
    assert @tree.root.join('fastq/DRA000/DRA000002/DRX000002/DRR000002_1.fastq.bz2').exist?

    assert @row.reload.status_private?
    assert @row.reads_built_at
    assert_equal 'reads built set 1 DRA submission to private', @submission.curation_events.sole.then { "#{it.actor_label} #{it.summary}" }
    assert_not BuildDRAReadsJob.kept_dir(@submission.id).exist?
  end

  # Stopped after a run was in the tree, the job is run again from the start.
  test 'a run in the tree already is not built again' do
    perform
    @row.update! status: :accession_issued, reads_built_at: nil

    assert_empty perform
    assert @row.reload.status_private?
  end

  # Made private by a curator before its reads were built.
  test 'one private and not built is built, and stays private' do
    @row.update! status: :private

    assert_equal 1, perform.size
    assert @row.reload.reads_built_at
    assert_empty @submission.curation_events
  end

  # Published meanwhile, it is built all the same.
  test 'one whose status changed during the build is marked built' do
    perform(->(**kwargs) { @row.update_columns(status: Lifecycleable::STATUSES.fetch('withdrawn')); built(**kwargs) })

    assert @row.reload.status_withdrawn?
    assert @row.reads_built_at
  end

  test 'what an earlier build of a run left in the tree goes' do
    dir = @tree.fastq_dir(submission: 'DRA000002', experiment: 'DRX000002').tap(&:mkpath)

    %w[DRR000002.fastq.bz2 DRR000002_1.fastq.bz2.partial DRR000003.fastq.bz2].each { dir.join(it).write('old') }

    perform

    assert_equal %w[DRR000002_1.fastq.bz2 DRR000002_2.fastq.bz2 DRR000003.fastq.bz2], dir.children.map { it.basename.to_s }.sort
  end

  test 'a run part of more than one experiment fails the job' do
    @submission.append_update! record.tap {|r|
      r['experiments'] << {'alias' => 'exp2', 'accession' => 'DRX000003'}
      r['relations'] << {'type' => 'part_of', 'source' => {'type' => 'run', 'alias' => 'run1'}, 'target' => {'db' => 'experiment', 'id' => 'exp2'}}
    }, actor: 'test'

    error = assert_raises(BuildDRAReadsJob::Failed) { perform }

    assert_match 'part of 2 experiments', error.message
  end

  test 'one not waiting for it is left alone' do
    @row.update! reads_built_at: Time.current

    assert_empty perform

    @row.update! status: :public, reads_built_at: nil

    assert_empty perform

    @row.update! status: :accession_issued
    @submission.update_columns source_id: 'DRA000002'

    assert_empty perform
    assert @row.reload.status_accession_issued?, "D-way's are built by D-way"
  end

  test 'reads that cannot be built fail the job and leave it waiting' do
    error = assert_raises(BuildDRAReadsJob::Failed) {
      perform(->(**) { DRA::ReadBuild::Result.new(ok: false, output: "latf-load err: bad\n", sra: nil, fastqs: []) })
    }

    assert_match "DRA000002: runs[0] (DRR000002) could not be built:\nlatf-load err: bad", error.message
    assert @row.reload.status_accession_issued?
    assert_not @tree.root.exist?
  end

  test 'a run of a filetype not built here fails the job, by name' do
    @submission.append_update! record([fastq('r_1.fastq').merge('filetype' => 'bam')]), actor: 'test'

    error = assert_raises(BuildDRAReadsJob::Failed) { perform }

    assert_match 'runs[0] is of bam files, which are not built here yet', error.message
  end

  # Two would build into one directory.
  test 'one is built by one run at a time' do
    AdvisoryLock.stub(:exclusively, ->(name, &) { raise AdvisoryLock::Held, name }) do
      assert_enqueued_with(job: BuildDRAReadsJob) { BuildDRAReadsJob.perform_now @submission }
    end

    assert @row.reload.status_accession_issued?
  end

  # In turn with the checks: the same tools over the same reads.
  test 'builds and checks share one limit' do
    assert_equal [CheckDRAReadsJob.new(nil).concurrency_key], [BuildDRAReadsJob.new(@submission).concurrency_key]
  end

  test 'a run whose file has gone, or that is part of no experiment, fails the job' do
    @submission.data_files_attachments.find_by(blob: ActiveStorage::Blob.where(filename: 'r_2.fastq').last).destroy!

    assert_raises(BuildDRAReadsJob::Failed) { perform }

    @submission.append_update! record([fastq('r_1.fastq')]).merge('relations' => []), actor: 'test'

    error = assert_raises(BuildDRAReadsJob::Failed) { perform }

    assert_match 'part of no experiment', error.message
  end

  # The test database has no Solid Queue tables.
  def enqueue_due = BuildDRAReadsJob.stub(:queued, Set.new) { BuildDRAReadsJob.enqueue_due }

  test 'enqueue_due starts one for each waiting with no job of its own' do
    assert_enqueued_with(job: BuildDRAReadsJob, args: [@submission]) do
      enqueue_due
    end

    dways = Submission.create!(db: 'dra', user: users(:alice), source_id: 'DRA000003')
    DRASubmission.create!(submission: dways, accession: 'DRA000003', status: :accession_issued)

    assert_no_enqueued_jobs(only: BuildDRAReadsJob) do
      BuildDRAReadsJob.stub(:queued, [@submission.to_global_id.to_s].to_set) do
        BuildDRAReadsJob.enqueue_due
      end
    end
  end

  test 'enqueue_due clears what was kept for one with no job' do
    kept = BuildDRAReadsJob.kept_dir(@submission.id).join('run-0').tap(&:mkpath)

    BuildDRAReadsJob.stub(:queued, [@submission.to_global_id.to_s].to_set) { BuildDRAReadsJob.enqueue_due }

    assert kept.exist?

    enqueue_due

    assert_not kept.exist?
  end
end
