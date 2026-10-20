require 'test_helper'

class DRA::ReadsTreeTest < ActiveSupport::TestCase
  setup do
    @dir  = Pathname.new(Dir.mktmpdir('reads-tree-test-'))
    @tree = DRA::ReadsTree.new(@dir)
  end

  teardown do
    @dir.rmtree
  end

  test 'lays reads out as on the FTP site' do
    assert_equal @dir.join('fastq/DRA000/DRA000001/DRX000001'), @tree.fastq_dir(submission: 'DRA000001', experiment: 'DRX000001')
    assert_equal @dir.join('sra/ByExp/sra/DRX/DRX000/DRX000001/DRR000001/DRR000001.sra'), @tree.sra(experiment: 'DRX000001', run: 'DRR000001')
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
