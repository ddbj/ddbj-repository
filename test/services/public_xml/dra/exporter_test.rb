require 'test_helper'

class PublicXML::DRA::ExporterTest < ActiveSupport::TestCase
  # The documents are in the public tree's fastq/; @withheld is the
  # private tree.
  setup do
    @root       = Pathname.new(Dir.mktmpdir)
    @output_dir = @root.join('public', 'fastq')
    @withheld   = DRA::ReadsTree.new(@root.join('private'))
    @row        = dra_submissions(:dra)

    @row.submission.append_update! record, actor: 'test'
    @row.update! status: :public, first_published_at: 1.week.ago, last_published_at: 1.week.ago
  end

  teardown do
    @root.rmtree if @root&.exist?
  end

  def record = JSON.parse(file_fixture('dra/record/DRA000001.json').read)

  def exporter(at: Time.current) = PublicXML::DRA::Exporter.new(tree: tree, withheld: @withheld, started_at: at)

  def export(...) = exporter(...).call

  def tree = DRA::ReadsTree.new(@output_dir.dirname)

  def directory = @output_dir.join('DRA000', 'DRA000001')

  def edit!(record)
    @row.submission.append_update! record, actor: 'test'
    @row.class.where(id: @row.id).republished!
  end

  test 'writes a document a kind into a directory of the submission' do
    run = export

    assert_equal %w[DRA000001.experiment.xml DRA000001.run.xml DRA000001.submission.xml], directory.children.map { it.basename.to_s }.sort
    assert_equal 'DRX000001', Nokogiri::XML(directory.join('DRA000001.experiment.xml').read).at_xpath('//EXPERIMENT/@accession').value

    assert run.completed_status?
    assert_equal 1, run.emitted
  end

  # The tree is tens of thousands of submissions.
  test 'writes again only what was published since it was written' do
    export

    assert_equal 0, export.emitted

    @row.class.where(id: @row.id).republished!

    assert_equal 1, export.emitted
  end

  # D-way's import dates a publication by D-way's own clock, which can be
  # before the last run here.
  test 'writes what was never written, however long ago it was published' do
    export

    other = Submission.create!(db: :dra, user: users(:alice), source_id: 'DRA000002')
    other.append_update! record.deep_merge('submission' => {'accession' => 'DRA000002'}), actor: 'test'
    other.create_dra_submission!(accession: 'DRA000002', status: :public, first_published_at: 1.year.ago, last_published_at: 1.year.ago)

    assert_equal 1, export.emitted
    assert @output_dir.join('DRA000', 'DRA000002', 'DRA000002.run.xml').exist?
  end

  test 'takes out what is no longer public, and nothing that is not a submission' do
    export

    @output_dir.join('DRA000', 'README').write('not ours')
    @output_dir.join('notes').mkpath

    @row.update! status: :temporarily_suppressed

    export

    assert_not directory.exist?
    assert @output_dir.join('DRA000', 'README').exist?
    assert @output_dir.join('notes').exist?
  end

  # D-way's import brings a submission back to public dated by D-way's
  # clock, which can be before it was last written here.
  test 'what comes back to public is written again, however it is dated' do
    export

    @row.update! status: :temporarily_suppressed
    export

    @row.update_columns status: Lifecycleable::STATUSES.fetch('public'), last_published_at: 1.month.ago

    assert_equal 1, export.emitted
    assert directory.join('DRA000001.run.xml').exist?
  end

  # A deploy stops a run part way; the next goes on from there.
  test 'a run stopped part way is gone on from' do
    stopped = exporter(at: 1.hour.ago)

    stopped.stub(:withdraw, -> { raise Interrupt }) do
      assert_raises(Interrupt) { stopped.call }
    end

    assert directory.join('DRA000001.run.xml').exist?
    assert_equal 0, export.emitted
  end

  # Its marker gone, the tree is written whole — and stopped part way at
  # that, the next run writes the rest rather than taking the marker the
  # stopped one left for a finished tree.
  test 'a tree written whole and stopped part way is finished by the next run' do
    other = Submission.create!(db: :dra, user: users(:alice), source_id: 'DRA000002')
    other.append_update! record.deep_merge('submission' => {'accession' => 'DRA000002'}), actor: 'test'
    other.create_dra_submission!(accession: 'DRA000002', status: :public, first_published_at: 1.week.ago, last_published_at: 1.week.ago)

    export(at: 1.day.ago)

    @output_dir.children.each(&:rmtree)

    stopped = exporter(at: 1.hour.ago)
    written = 0
    write   = stopped.method(:write)

    stopped.stub(:write, ->(row) { (written += 1) > 1 ? raise(Interrupt) : write.(row) }) do
      assert_raises(Interrupt) { stopped.call }
    end

    assert_equal 1, export.emitted
    assert @output_dir.join('DRA000', 'DRA000001', 'DRA000001.run.xml').exist?
    assert @output_dir.join('DRA000', 'DRA000002', 'DRA000002.run.xml').exist?
  end

  # The tree is the one the SRA mirror puts NCBI's and EBI's submissions
  # in, and D-way's own that the import left out; one of D-way's it has a
  # row for is taken out though nothing here wrote it.
  test 'takes out only what it has rows for, whoever wrote it' do
    others = [
      @output_dir.join('SRA000', 'SRA000999'),
      @output_dir.join('ERA000', 'ERA000999'),
      @output_dir.join('DRA000', 'DRA000999')
    ].each(&:mkpath)

    dways = directory.tap(&:mkpath).join('DRA000001.run.xml').tap { it.write('<RUN_SET/>') }

    @row.update! status: :temporarily_suppressed

    export

    assert others.all?(&:exist?)
    assert_not dways.exist?
  end

  def sra(tree) = tree.sra(experiment: 'DRX000001', run: 'DRR000001')

  def fastq(tree) = tree.fastq_dir(submission: 'DRA000001', experiment: 'DRX000001').join('DRR000001_1.fastq.bz2')

  def put(path, body = 'reads') = path.tap { it.dirname.mkpath }.tap { it.write(body) }

  # Built into the private tree (BuildDRAReadsJob), as on the FTP site.
  test 'what was built goes public with the documents, and the private tree is left with nothing of it' do
    @row.update_columns status: Lifecycleable::STATUSES.fetch('private')

    put fastq(@withheld)
    put sra(@withheld)
    put @withheld.analysis_dir(submission: 'DRA000001', analysis: 'DRZ000001').join('aln.bam')

    @row.update! status: :public

    export

    assert_equal 'reads', fastq(tree).read
    assert_equal 'reads', sra(tree).read
    assert tree.analysis_dir(submission: 'DRA000001', analysis: 'DRZ000001').join('aln.bam').exist?
    assert directory.join('DRA000001.run.xml').exist?

    assert_empty @withheld.root.glob('**/*').select(&:file?)
    assert_not sra(@withheld).dirname.exist?, 'the directories the .sra leaves empty go'
    assert_not @withheld.submission_dir('DRA000001').exist?
  end

  # The tree is shared, and a link in it leads anywhere.
  test 'nothing is moved through a link, nor anything not named as an object' do
    export

    elsewhere = put(@root.join('elsewhere', 'DRR000001.fastq.bz2'))
    directory.join('DRX000009').make_symlink(elsewhere.dirname)
    put directory.join('notes', 'a.txt')

    @row.update! status: :temporarily_suppressed

    export

    assert elsewhere.exist?
    assert directory.join('notes', 'a.txt').exist?
    assert_empty @withheld.root.glob('**/*').select(&:file?)
  end

  # In the public tree it would be served.
  test 'what a move stopped while copying left goes, from either tree' do
    put fastq(tree)
    export

    partial = put(fastq(tree).sub_ext('.bz2.partial'))

    @row.update! status: :temporarily_suppressed

    export

    assert_not partial.exist?
    assert_not directory.exist?
  end

  # Its experiment changed since: the .sra is filed under the one it was
  # built for.
  test "one sent here whose run's .sra is not where its record files it is not published" do
    @row.submission.update_columns source_id: nil
    @row.update_columns public_xml_written_at: nil

    put fastq(@withheld)

    run = export

    assert_match 'DRA000001: its reads are not where they were built: DRR000001', run.error_log
    assert fastq(@withheld).exist?
    assert_not directory.exist?
  end

  # In D-way's tree a submission's reads are in its directory; taken out,
  # they are kept, to be published again.
  test 'taken out, its files go back to the private tree and its documents go' do
    put fastq(tree)
    put sra(tree)
    export

    sras = sra(tree).dirname.dirname.dirname.join('DRX000002').tap(&:mkpath)

    @row.update! status: :temporarily_suppressed

    export

    assert_equal 'reads', fastq(@withheld).read
    assert_equal 'reads', sra(@withheld).read
    assert_not directory.exist?
    assert_not sra(tree).exist?
    assert sras.exist?, "the mirror's beside it stay"

    @row.update! status: :public

    export

    assert_equal 'reads', fastq(tree).read
    assert_equal 'reads', sra(tree).read
  end

  # Moved one at a time; what went across is not there to move again.
  test 'files moved part way are moved the rest of the way by the next run' do
    put fastq(@withheld)
    put sra(@withheld)
    @row.update_columns public_xml_written_at: nil

    moved = 0
    move  = DRA::ReadsTree.method(:move)

    DRA::ReadsTree.stub(:move, ->(*args) { (moved += 1) > 1 ? raise(Interrupt) : move.(*args) }) do
      assert_raises(Interrupt) { export }
    end

    export

    assert fastq(tree).exist?
    assert sra(tree).exist?
  end

  test 'one whose files cannot be known is not taken out, and says so' do
    export

    @row.update! status: :temporarily_suppressed

    SubmissionUpdate.create_with_patch!(
      submission:              @row.submission,
      patch_json:              'not-json',
      db:                      'dra',
      status:                  :applied,
      actor:                   'test',
      source:                  :manual,
      patch_canonical_version: DDBJRecord::Canonicalizer::NUMBER
    )

    run = export

    assert_match(/\ADRA000001: not taken out, its files not known/, run.error_log)
    assert directory.join('DRA000001.run.xml').exist?
    assert @row.reload.public_xml_written_at, 'tried again by the next run'
  end

  # D-way's import dates the first publication by its release date, which
  # it may not have.
  test 'takes out what it wrote, though nothing dates its publication' do
    @row.update_columns first_published_at: nil

    export

    @row.update! status: :temporarily_suppressed

    export

    assert_not directory.exist?
    assert_nil @row.reload.public_xml_written_at
  end

  # Its row written, though nothing dates its publication: what says it is
  # to be taken out is that it was written.
  test 'a withdrawal stopped part way is taken up again' do
    @row.update_columns first_published_at: nil

    export

    @row.update! status: :temporarily_suppressed

    stopped = exporter

    FileUtils.stub(:rm_f, ->(*) { raise Interrupt }) do
      assert_raises(Interrupt) { stopped.call }
    end

    export

    assert_not directory.exist?
  end

  # Not this run's to take: one never public was put there by D-way, whose
  # status for it this may be behind.
  test 'leaves what was never public' do
    @row.update! status: :private, first_published_at: nil, last_published_at: nil

    dways = directory.tap(&:mkpath).join('DRA000001.run.xml').tap { it.write('<RUN_SET/>') }

    export

    assert dways.exist?
  end

  # The 27 earliest DRA submissions are numbered SRA.
  test 'takes out an SRA-numbered submission no longer public' do
    @row.update_columns accession: 'SRA000001'
    @row.submission.append_update! record.deep_merge('submission' => {'accession' => 'SRA000001'}), actor: 'test'

    export

    assert @output_dir.join('SRA000', 'SRA000001').exist?

    @row.update! status: :temporarily_suppressed

    export

    assert_not @output_dir.join('SRA000', 'SRA000001').exist?
  end

  # One record that does not render as the version takes it leaves what
  # was there, and holds up nothing else: it is tried again each night.
  test 'a submission that cannot be published is listed, left as it was, and tried again' do
    export
    written = directory.join('DRA000001.experiment.xml').read

    edit! record.tap { it['experiments'][0]['library']['strategy'] = 'Guesswork' }

    run = export

    assert run.completed_status?
    assert_match(/\ADRA000001: experiment: .*LIBRARY_STRATEGY/, run.error_log)
    assert_equal written, directory.join('DRA000001.experiment.xml').read

    assert_match(/\ADRA000001: /, export.error_log, 'tried again')

    edit! record

    assert_equal 1, export.emitted
  end

  # The tree lives on a mount: what was written into a directory standing
  # in for it is written again once it is back, though nothing about the
  # submission has changed since.
  test 'a tree that missed what was written elsewhere has it written again' do
    export(at: 2.days.ago)

    real        = @output_dir
    @output_dir = @root.join('standing-in', 'fastq')

    export(at: 1.day.ago)

    @output_dir = real

    assert_equal 1, export.emitted
    assert_equal 0, export.emitted
  end

  test 'a tree with nothing in it is written whole' do
    export

    @output_dir.children.each(&:rmtree)

    assert_equal 1, export.emitted
  end

  test 'a kind the record no longer has is taken out' do
    export

    edit! record.except('submission')

    export

    assert_not directory.join('DRA000001.submission.xml').exist?
    assert directory.join('DRA000001.experiment.xml').exist?
  end

  # A run stopped between writing and renaming leaves the row due, of a
  # kind the record may no longer have — or that it cannot publish now.
  test 'a document left half written is cleared away' do
    export

    directory.join('DRA000001.analysis.xml.partial').write('<ANALYSIS_SET>')
    edit! record.tap { it['experiments'][0]['library']['strategy'] = 'Guesswork' }

    export

    assert_not directory.join('DRA000001.analysis.xml.partial').exist?
  end
end
