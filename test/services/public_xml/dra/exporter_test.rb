require 'test_helper'

class PublicXML::DRA::ExporterTest < ActiveSupport::TestCase
  setup do
    @output_dir = Pathname.new(Dir.mktmpdir)
    @row        = dra_submissions(:dra)

    @row.submission.append_update! record, actor: 'test'
    @row.update! status: :public, first_published_at: 1.week.ago, last_published_at: 1.week.ago
  end

  teardown do
    @output_dir.rmtree if @output_dir&.exist?
  end

  def record = JSON.parse(file_fixture('dra/record/DRA000001.json').read)

  def export(at: Time.current) = PublicXML::DRA::Exporter.new(output_dir: @output_dir, started_at: at).call

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
    stopped = PublicXML::DRA::Exporter.new(output_dir: @output_dir, started_at: 1.hour.ago)

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

    stopped = PublicXML::DRA::Exporter.new(output_dir: @output_dir, started_at: 1.hour.ago)
    written = 0
    write   = stopped.method(:write)

    stopped.stub(:write, ->(row) { (written += 1) > 1 ? raise(Interrupt) : write.(row) }) do
      assert_raises(Interrupt) { stopped.call }
    end

    assert_equal 1, export.emitted
    assert @output_dir.join('DRA000', 'DRA000001', 'DRA000001.run.xml').exist?
    assert @output_dir.join('DRA000', 'DRA000002', 'DRA000002.run.xml').exist?
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
    @output_dir = Pathname.new(Dir.mktmpdir)

    export(at: 1.day.ago)

    @output_dir.rmtree
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

  # A run stopped between writing and renaming.
  test 'a document left half written is cleared away' do
    export

    directory.join('DRA000001.run.xml.partial').write('<RUN_SET>')

    export

    assert_not directory.join('DRA000001.run.xml.partial').exist?
  end
end
