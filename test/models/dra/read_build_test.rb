require 'test_helper'

class DRA::ReadBuildTest < ActiveSupport::TestCase
  # A pair as an Illumina instrument names it.
  READ1 = "@A00123:8:H5KYVDSXX:1:1101:1000:1000 1:N:0:ACGTACGT\nACGTACGTAC\n+\nIIIIIIIIII\n" \
          "@A00123:8:H5KYVDSXX:1:1101:1000:2000 1:N:0:ACGTACGT\nTTTTGGGGCC\n+\nIIIIIIIIII\n"
  READ2 = "@A00123:8:H5KYVDSXX:1:1101:1000:1000 2:N:0:ACGTACGT\nGGGGCCCCAA\n+\nIIIIIIIIII\n" \
          "@A00123:8:H5KYVDSXX:1:1101:1000:2000 2:N:0:ACGTACGT\nCCAATTGGAA\n+\nIIIIIIIIII\n"

  setup do
    @work_dir = Pathname.new(Dir.mktmpdir('read-build-test-'))
  end

  teardown do
    @work_dir.rmtree
  end

  def blob(body, filename)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(body), filename:, content_type: 'application/octet-stream')
  end

  # Tools that say what they were given and make what the real ones would
  # (`kar -c`'s file, fastq-dump's pair, pbzip2's .bz2), unless `exit` has
  # them fail.
  def fake_toolkit(exit: {})
    @work_dir.join("fake-toolkit-#{SecureRandom.hex(4)}").tap {|dir|
      dir.mkpath

      {
        'latf-load'  => '',
        'kar'        => 'echo sra > "$2"',
        'fastq-dump' => 'mkdir -p "$6"; echo r1 > "$6/$4_1.fastq"; echo r2 > "$6/$4_2.fastq"',
        'pbzip2'     => 'bzip2 -f "$3"'
      }.each do |tool, body|
        dir.join(tool).write(<<~SH)
          #!/bin/sh
          echo "#{tool}: $*"
          [ #{exit.fetch(tool, 0)} -eq 0 ] || exit #{exit.fetch(tool, 0)}
          #{body}
        SH

        dir.join(tool).chmod(0o755)
      end
    }
  end

  def build(files, toolkit:, filetype: 'fastq')
    path = ENV.fetch('PATH')

    ENV['PATH'] = "#{toolkit}#{File::PATH_SEPARATOR}#{path}"

    DRA::ReadBuild.call(files:, filetype:, accession: 'DRR000001', platform: 'ILLUMINA', toolkit:, dir: @work_dir.join('run'))
  ensure
    ENV['PATH'] = path
  end

  test 'fastq is loaded, packed into the run\'s .sra, and dumped by its accession into bz2' do
    result = build([blob(READ1, 'r_1.fastq'), blob(READ2, 'r_2.fastq')], toolkit: fake_toolkit)

    assert result.ok?, result.output
    assert_match(/latf-load: --quality PHRED_33 --platform ILLUMINA .* -o \S+out \S+r_1\.fastq \S+r_2\.fastq/, result.output)
    assert_match(/kar: -c \S+DRR000001\.sra -d \S+out/, result.output)
    assert_match(/fastq-dump: --split-3 --skip-technical -A DRR000001 -O \S+dump \S+DRR000001\.sra/, result.output)

    assert_equal 'DRR000001.sra', result.sra.basename.to_s
    assert_equal %w[DRR000001_1.fastq.bz2 DRR000001_2.fastq.bz2], result.fastqs.map { it.basename.to_s }
  end

  test 'an sra file sent is the run\'s .sra' do
    result = build([blob('sent', 'run.sra')], toolkit: fake_toolkit, filetype: 'sra')

    assert result.ok?, result.output
    assert_no_match 'latf-load', result.output
    assert_equal 'sent', result.sra.read
  end

  test 'a run sent as more than one sra file is not built' do
    result = build([blob('a', 'a.sra'), blob('b', 'b.sra')], toolkit: fake_toolkit, filetype: 'sra')

    assert_not result.ok?
    assert_match 'a run sent as SRA is one file', result.output
  end

  test 'what a tool refuses ends it, with what it said' do
    %w[latf-load kar fastq-dump pbzip2].each do |tool|
      result = build([blob(READ1, 'r.fastq')], toolkit: fake_toolkit(exit: {tool => 3}))

      assert_not result.ok?, tool
      assert_match "#{tool}: ", result.output
      assert_nil result.sra
      assert_empty result.fastqs
    end
  end

  test 'a host without the tools says so' do
    assert_raises(DRA::SRAToolkit::ToolMissing) { build([blob(READ1, 'r.fastq')], toolkit: @work_dir.join('nowhere')) }
  end
end

# With the real SRA Toolkit and pbzip2, where they are installed (the
# image, and CI).
class DRA::ReadBuildWithSRAToolkitTest < ActiveSupport::TestCase
  TOOLS = %w[latf-load kar fastq-dump pbzip2].freeze

  setup do
    skip "#{TOOLS.join(', ')} are not all on PATH" unless TOOLS.all? { DRA::SRAToolkit.path(it) }

    @work_dir = Pathname.new(Dir.mktmpdir('read-build-test-'))
  end

  teardown do
    @work_dir&.rmtree
  end

  def blob(body, filename)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(body), filename:, content_type: 'application/octet-stream')
  end

  test 'a pair is built into an .sra that gives the pair back, named by the run' do
    files  = [blob(DRA::ReadBuildTest::READ1, 'r_1.fastq'), blob(DRA::ReadBuildTest::READ2, 'r_2.fastq')]
    result = DRA::ReadBuild.call(files:, filetype: 'fastq', accession: 'DRR000001', platform: 'ILLUMINA', dir: @work_dir.join('run'))

    assert result.ok?, result.output
    assert_equal %w[DRR000001_1.fastq.bz2 DRR000001_2.fastq.bz2], result.fastqs.map { it.basename.to_s }

    first = IO.popen(['bzip2', '-dc', result.fastqs.first.to_s], &:read)

    assert_match(/\A@DRR000001\.1 A00123:8:H5KYVDSXX:1:1101:1000:1000 length=10\nACGTACGTAC\n/, first)
  end
end
