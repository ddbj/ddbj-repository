require 'test_helper'

class DRA::ReadsTreeTest < ActiveSupport::TestCase
  setup do
    @dir  = Pathname.new(Dir.mktmpdir('reads-tree-test-'))
    @tree = DRA::ReadsTree.new(dra: @dir.join('dra'), sra: @dir.join('sra'))
  end

  teardown do
    @dir.rmtree
  end

  test 'lays reads out as on the FTP site' do
    assert_equal @dir.join('dra/fastq/DRA000/DRA000001/DRX000001'), @tree.fastq_dir(submission: 'DRA000001', experiment: 'DRX000001')
    assert_equal @dir.join('dra/sra/ByExp/sra/DRX/DRX000/DRX000001/DRR000001/DRR000001.sra'), @tree.sra(experiment: 'DRX000001', run: 'DRR000001')
    assert_equal @dir.join('sra/DRR/000/123/456/DRR123456/submitted'), @tree.submitted_dir(run: 'DRR123456')
  end

  test 'a path is named by the tree it is in' do
    assert_equal [:sra, Pathname.new('DRR/000/000/001/DRR000001/submitted/a.fq')], @tree.locate(@tree.submitted_dir(run: 'DRR000001').join('a.fq'))
    assert_raises(ArgumentError) { @tree.locate(@dir.join('dra-other', 'x')) }
  end

  test "a run's fastq are its own, however many" do
    dir = @tree.fastq_dir(submission: 'DRA000001', experiment: 'DRX000001').tap(&:mkpath)

    %w[DRR000001.fastq.bz2 DRR000001_1.fastq.bz2 DRR000001_2.fastq.bz2 DRR0000010_1.fastq.bz2 DRR000001_1.fastq.bz2.partial].each { dir.join(it).write('') }

    assert_equal %w[DRR000001.fastq.bz2 DRR000001_1.fastq.bz2 DRR000001_2.fastq.bz2], @tree.fastqs(submission: 'DRA000001', experiment: 'DRX000001', run: 'DRR000001').map { it.basename.to_s }
  end

  test 'a move across mounts is a copy under another name, renamed, then the original removed' do
    file = @dir.join('built.sra').tap { it.write('sra') }
    path = @tree.sra(experiment: 'DRX000001', run: 'DRR000001')

    file.define_singleton_method(:rename) {|*| raise Errno::EXDEV }

    DRA::ReadsTree.move file, path

    assert_equal 'sra', path.read
    assert_not file.exist?
    assert_not path.sub_ext('.sra.partial').exist?
  end
end
