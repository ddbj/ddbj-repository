require 'test_helper'

class PublicXML::DRA::ExporterTest < ActiveSupport::TestCase
  MOVER = Rails.root.join('script/dra-mover').to_s

  # The public tree is written only by the mover (#move!), as on the
  # host; the run writes the private one and asks.
  setup do
    @root     = Pathname.new(Dir.mktmpdir)
    @tree     = DRA::ReadsTree.new(dra: @root.join('public', 'dra').tap(&:mkpath), sra: @root.join('public', 'sra').tap(&:mkpath))
    @withheld = DRA::ReadsTree.new(dra: @root.join('private', 'dra').tap(&:mkpath), sra: @root.join('private', 'sra').tap(&:mkpath))
    @requests = DRA::PublicationRequests.new(@root.join('private', 'requests').tap(&:mkpath))
    @row      = dra_submissions(:dra)

    @row.submission.append_update! record, actor: 'test'
    @row.update! status: :public, first_published_at: 1.week.ago, last_published_at: 1.week.ago
  end

  teardown do
    @root.rmtree if @root&.exist?
  end

  def record = JSON.parse(file_fixture('dra/record/DRA000001.json').read)

  def exporter(at: Time.current) = PublicXML::DRA::Exporter.new(tree: @tree, withheld: @withheld, requests: @requests, started_at: at)

  def export(...) = exporter(...).call

  def move!
    trees = %i[dra sra].flat_map { ['--tree', "#{it}=#{@tree.roots[it]}:#{@withheld.roots[it]}:#{hold(it)}"] }

    system 'python3', MOVER, '--quiet', '--requests', @requests.root.to_s, '--lock', @root.join('mover.lock').to_s, *trees, exception: true
  end

  def hold(tree) = @root.join("#{tree}-hold").tap { it.mkpath }.tap { it.chmod(0o700) }

  # A run, and the mover after it: what a night does.
  def publish(...) = export(...).tap { move! }

  def directory = @tree.submission_dir('DRA000001')

  def edit!(record)
    @row.submission.append_update! record, actor: 'test'
    @row.class.where(id: @row.id).republished!
  end

  def sra(tree) = tree.sra(experiment: 'DRX000001', run: 'DRR000001')

  def fastq(tree) = tree.fastq_dir(submission: 'DRA000001', experiment: 'DRX000001').join('DRR000001_1.fastq.bz2')

  def submitted(tree) = tree.submitted_dir(run: 'DRR000001').join('reads_1.fq.gz')

  def put(path, body = 'reads') = path.tap { it.dirname.mkpath }.tap { it.write(body) }

  test 'asks for a document a kind to go into a directory of the submission' do
    run = publish

    assert_equal %w[DRA000001.experiment.xml DRA000001.run.xml DRA000001.submission.xml], directory.children.map { it.basename.to_s }.sort
    assert_equal 'DRX000001', Nokogiri::XML(directory.join('DRA000001.experiment.xml').read).at_xpath('//EXPERIMENT/@accession').value
    assert_not @withheld.submission_dir('DRA000001').exist?, 'nothing is left behind'

    assert run.completed_status?
    assert_equal 1, run.emitted
  end

  # The tree is tens of thousands of submissions.
  test 'asks again only for what was published since, once it is done' do
    publish

    assert_nil @row.reload.public_xml_written_at, 'not until the next run reads what came of it'
    assert_equal 0, publish.emitted
    assert @row.reload.public_xml_written_at

    @row.class.where(id: @row.id).republished!

    assert_equal 1, export.emitted
  end

  # Two requests for one submission could cross.
  test 'asks nothing more of one whose request is waiting' do
    export

    assert_equal 0, export.emitted

    @row.update! status: :temporarily_suppressed

    export
    move!

    assert directory.join('DRA000001.run.xml').exist?, 'its withdrawal waits its turn'

    publish

    assert_not directory.exist?
  end

  # D-way's import dates a publication by D-way's own clock, which can be
  # before the last run here.
  test 'asks for what was never written, however long ago it was published' do
    publish
    export

    other = Submission.create!(db: :dra, user: users(:alice), source_id: 'DRA000002')
    other.append_update! record.deep_merge('submission' => {'accession' => 'DRA000002'}), actor: 'test'
    other.create_dra_submission!(accession: 'DRA000002', status: :public, first_published_at: 1.year.ago, last_published_at: 1.year.ago)

    assert_equal 1, publish.emitted
    assert @tree.submission_dir('DRA000002').join('DRA000002.run.xml').exist?
  end

  # Taken out by hand, or the tree restored from before.
  test 'asks again for what has gone from the tree' do
    publish
    export

    directory.rmtree

    assert_equal 1, publish.emitted
    assert directory.join('DRA000001.run.xml').exist?
  end

  test 'takes out what is no longer public, and nothing that is not a submission' do
    publish
    export

    put @tree.roots[:dra].join('fastq', 'DRA000', 'README'), 'not ours'
    @tree.roots[:dra].join('fastq', 'notes').mkpath

    @row.update! status: :temporarily_suppressed

    publish
    export

    assert_not directory.exist?
    assert @tree.roots[:dra].join('fastq', 'DRA000', 'README').exist?
    assert @tree.roots[:dra].join('fastq', 'notes').exist?
    assert_nil @row.reload.public_xml_written_at
  end

  # D-way's import brings a submission back to public dated by D-way's
  # clock, which can be before it was last written here.
  test 'what comes back to public is asked for again, however it is dated' do
    publish
    export

    @row.update! status: :temporarily_suppressed
    publish
    export

    @row.update_columns status: Lifecycleable::STATUSES.fetch('public'), last_published_at: 1.month.ago

    assert_equal 1, publish.emitted
    assert directory.join('DRA000001.run.xml').exist?
  end

  # A deploy stops a run part way; the next goes on from there.
  test 'a run stopped part way is gone on from' do
    stopped = exporter(at: 1.hour.ago)

    stopped.stub(:withdraw, ->(*) { raise Interrupt }) do
      assert_raises(Interrupt) { stopped.call }
    end

    move!

    assert directory.join('DRA000001.run.xml').exist?
    assert_equal 0, export.emitted
    assert_equal 0, export.emitted
  end

  test 'what the mover could not do is said on the next run, and asked for again' do
    export

    @withheld.submission_dir('DRA000001').join('DRA000001.run.xml').delete
    move!

    run = export

    assert_match %r{\ADRA000001: not published: in neither tree: dra/fastq/DRA000/DRA000001/DRA000001.run.xml}, run.error_log
    assert_equal 1, run.emitted

    move!
    export

    assert directory.join('DRA000001.run.xml').exist?
  end

  # The tree is the one the SRA mirror puts NCBI's and EBI's submissions
  # in, and D-way's own that the import left out; one of D-way's it has a
  # row for is taken out though nothing here wrote it.
  test 'takes out only what it has rows for, whoever wrote it' do
    others = [
      @tree.submission_dir('SRA000999'),
      @tree.submission_dir('ERA000999'),
      @tree.submission_dir('DRA000999')
    ].each(&:mkpath)

    dways = put(directory.join('DRA000001.run.xml'), '<RUN_SET/>')

    @row.update! status: :temporarily_suppressed

    publish

    assert others.all?(&:exist?)
    assert_not dways.exist?
    assert_equal '<RUN_SET/>', @withheld.submission_dir('DRA000001').join('DRA000001.run.xml').read
  end

  # Built into the private tree (BuildDRAReadsJob), as on the FTP site.
  test 'what was built goes public with the documents, and the private tree is left with nothing of it' do
    @row.update_columns status: Lifecycleable::STATUSES.fetch('private')

    put fastq(@withheld)
    put sra(@withheld)
    put submitted(@withheld)
    put @withheld.analysis_dir(submission: 'DRA000001', analysis: 'DRZ000001').join('aln.bam')

    @row.update! status: :public

    publish

    assert_equal 'reads', fastq(@tree).read
    assert_equal 'reads', sra(@tree).read
    assert_equal 'reads', @tree.roots[:sra].join('DRR/000/000/001/DRR000001/submitted/reads_1.fq.gz').read
    assert @tree.analysis_dir(submission: 'DRA000001', analysis: 'DRZ000001').join('aln.bam').exist?
    assert directory.join('DRA000001.run.xml').exist?

    assert_empty @withheld.roots.values.flat_map { it.glob('**/*') }.select(&:file?)
    assert_not sra(@withheld).dirname.exist?, 'the directories the .sra leaves empty go'
    assert @withheld.roots[:dra].join('sra/ByExp/sra/DRX/DRX000').exist?, 'but not the ones above them'
    assert_not @withheld.roots[:sra].join('DRR/000/000/001/DRR000001').exist?, 'nor those the files as sent leave'
    assert @withheld.roots[:sra].join('DRR/000/000/001').exist?
    assert_not @withheld.submission_dir('DRA000001').exist?
  end

  # A copy stopped part way into the private tree (DRA::ReadsTree.move).
  test 'a file half copied is not published' do
    put fastq(@withheld)
    put sra(@withheld)
    partial = put(fastq(@withheld).sub_ext('.bz2.partial'))

    publish

    assert partial.exist?
    assert_not fastq(@tree).sub_ext('.bz2.partial').exist?
  end

  # The tree is shared, and a link in it leads anywhere.
  test 'nothing is moved through a link, nor anything not named as an object' do
    publish
    export

    elsewhere = put(@root.join('elsewhere', 'DRR000001.fastq.bz2'))
    directory.join('DRX000009').make_symlink(elsewhere.dirname)
    put directory.join('notes', 'a.txt')

    @row.update! status: :temporarily_suppressed

    publish

    assert elsewhere.exist?
    assert directory.join('notes', 'a.txt').exist?
    assert_empty @withheld.roots[:dra].glob('**/*.fastq.bz2')
  end

  test "one sent here whose run's files as sent are in neither tree is not published" do
    @row.submission.update_columns source_id: nil

    put sra(@withheld)

    run = publish

    assert_match 'DRA000001: its reads are not where they were built: DRR000001', run.error_log
    assert_not directory.exist?

    put submitted(@withheld)

    publish

    assert submitted(@tree).exist?
    assert directory.exist?
  end

  # Its experiment changed since: the .sra is filed under the one it was
  # built for.
  test "one sent here whose run's .sra is not where its record files it is not published" do
    @row.submission.update_columns source_id: nil

    put fastq(@withheld)

    run = publish

    assert_match 'DRA000001: its reads are not where they were built: DRR000001', run.error_log
    assert fastq(@withheld).exist?
    assert_not directory.exist?
  end

  # In D-way's tree a submission's reads are in its directory; taken out,
  # they are kept, to be published again.
  test 'taken out, its documents and files go back to the private tree' do
    put fastq(@tree)
    put sra(@tree)
    put submitted(@tree)
    publish
    export

    mirrors = sra(@tree).dirname.dirname.dirname.join('DRX000002').tap(&:mkpath)

    @row.update! status: :temporarily_suppressed

    publish
    export

    assert_equal 'reads', fastq(@withheld).read
    assert_equal 'reads', sra(@withheld).read
    assert_equal 'reads', submitted(@withheld).read
    assert_not directory.exist?
    assert_not sra(@tree).exist?
    assert_not submitted(@tree).dirname.dirname.exist?
    assert mirrors.exist?, "the mirror's beside it stay"

    @row.update! status: :public

    publish

    assert_equal 'reads', fastq(@tree).read
    assert_equal 'reads', sra(@tree).read
    assert_equal 'reads', submitted(@tree).read
  end

  test 'one whose files cannot be known is not taken out, and says so' do
    publish
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

    run = publish

    assert_match(/\ADRA000001: not taken out, its files not known/, run.error_log)
    assert directory.join('DRA000001.run.xml').exist?
    assert @row.reload.public_xml_written_at, 'tried again by the next run'
  end

  # D-way's import dates the first publication by its release date, which
  # it may not have.
  test 'takes out what it wrote, though nothing dates its publication' do
    @row.update_columns first_published_at: nil

    publish
    export

    @row.update! status: :temporarily_suppressed

    publish
    export

    assert_not directory.exist?
    assert_nil @row.reload.public_xml_written_at
  end

  # Not this run's to take: one never public was put there by D-way, whose
  # status for it this may be behind.
  test 'leaves what was never public' do
    @row.update! status: :private, first_published_at: nil, last_published_at: nil

    dways = put(directory.join('DRA000001.run.xml'), '<RUN_SET/>')

    publish

    assert dways.exist?
  end

  # The 27 earliest DRA submissions are numbered SRA, in a tree with
  # NCBI's SRA… beside them: not the mover's to touch.
  test "leaves an SRA-numbered submission as it is, and says when it is a person's to take out" do
    @row.update_columns accession: 'SRA000001'
    @row.submission.append_update! record.deep_merge('submission' => {'accession' => 'SRA000001'}), actor: 'test'

    dways = put(@tree.submission_dir('SRA000001').join('SRA000001.run.xml'), '<RUN_SET/>')

    assert_equal 0, publish.emitted

    @row.update! status: :temporarily_suppressed

    assert_equal 'SRA000001: numbered SRA, which the mover does not take out; to be taken out by hand', publish.error_log
    assert dways.exist?
    assert_empty @requests.root.glob('**/*.json')
  end

  # One record that does not render as the version takes it leaves what
  # was there, and holds up nothing else: it is tried again each night.
  test 'a submission that cannot be published is listed, left as it was, and tried again' do
    publish
    export
    written = directory.join('DRA000001.experiment.xml').read

    edit! record.tap { it['experiments'][0]['library']['strategy'] = 'Guesswork' }

    run = publish

    assert run.completed_status?
    assert_match(/\ADRA000001: experiment: .*LIBRARY_STRATEGY/, run.error_log)
    assert_equal written, directory.join('DRA000001.experiment.xml').read

    assert_match(/\ADRA000001: /, export.error_log, 'tried again')

    edit! record

    assert_equal 1, export.emitted
  end

  test 'a kind the record no longer has is taken out' do
    publish
    export

    edit! record.except('submission')

    publish

    assert_not directory.join('DRA000001.submission.xml').exist?
    assert directory.join('DRA000001.experiment.xml').exist?
    assert_not @withheld.submission_dir('DRA000001').join('DRA000001.experiment.xml').exist?

    assert_equal 0, publish.emitted, 'what it has is in the tree'
  end

  # Published when the run reached it, and suppressed before the run took
  # out what had left.
  test 'one is asked about once a run, whatever becomes of it meanwhile' do
    publish
    export
    @row.class.where(id: @row.id).republished!

    run = exporter
    run.define_singleton_method(:write) {|row| super(row).tap { row.update_columns status: Lifecycleable::STATUSES.fetch('temporarily_suppressed') } }
    run.call

    assert_equal ['publish'], @requests.root.glob('*.json').map { it.basename('.json').to_s.split('-').last }
  end

  # A withdrawal failing part way is to be taken up by the next run, which
  # goes by the submission's directory.
  test "a submission's directory goes last" do
    put fastq(@tree)
    put sra(@tree)
    put submitted(@tree)
    publish
    export

    @row.update! status: :temporarily_suppressed

    export

    moves = JSON.parse(@requests.root.glob('*.json').sole.read)['moves'].map { [it['tree'], File.extname(it['path'])] }

    assert_equal [%w[dra .xml], %w[dra .xml], %w[dra .xml], %w[dra .sra], %w[sra .gz], %w[dra .bz2]], moves
  end

  test 'what is not a request is put aside, and said' do
    put @requests.root.join('done', 'notes.json'), '{}'

    run = export

    assert_match 'done/notes.json is not a request; put aside in unreadable/notes.json', run.error_log
    assert @requests.root.join('unreadable', 'notes.json').exist?
    assert_equal 1, run.emitted
  end

  # What the mover said goes with the requests it came of.
  test 'what the mover said is kept on a run that fails' do
    export
    @withheld.submission_dir('DRA000001').join('DRA000001.run.xml').delete
    move!

    stopped = exporter

    stopped.stub(:withdraw, ->(*) { raise IOError, 'disk' }) do
      assert_raises(IOError) { stopped.call }
    end

    assert_match 'DRA000001: not published: in neither tree', PublicXMLRun.order(:id).last.error_log
  end

  # A run stopped between writing and renaming leaves the row due, of a
  # kind the record may no longer have — or that it cannot publish now.
  test 'a document left half written is cleared away' do
    partial = put(@withheld.submission_dir('DRA000001').join('DRA000001.analysis.xml.partial'), '<ANALYSIS_SET>')

    edit! record.tap { it['experiments'][0]['library']['strategy'] = 'Guesswork' }

    export

    assert_not partial.exist?
  end
end
