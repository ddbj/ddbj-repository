require 'test_helper'

class DRA::ReadCheckTest < ActiveSupport::TestCase
  # A pair as an Illumina instrument names it: one read per file, the same
  # spot in each.
  READ1     = "@A00123:8:H5KYVDSXX:1:1101:1000:1000 1:N:0:ACGTACGT\nACGTACGTAC\n+\nIIIIIIIIII\n" \
              "@A00123:8:H5KYVDSXX:1:1101:1000:2000 1:N:0:ACGTACGT\nTTTTGGGGCC\n+\nIIIIIIIIII\n"
  READ2     = "@A00123:8:H5KYVDSXX:1:1101:1000:1000 2:N:0:ACGTACGT\nGGGGCCCCAA\n+\nIIIIIIIIII\n" \
              "@A00123:8:H5KYVDSXX:1:1101:1000:2000 2:N:0:ACGTACGT\nCCAATTGGAA\n+\nIIIIIIIIII\n"
  MALFORMED = "@r1\nACGTACGTAC\n+\nIII\n"

  setup do
    @work_dir = Pathname.new(Dir.mktmpdir('read-check-test-'))
  end

  teardown do
    @work_dir.rmtree
  end

  def blob(body, filename)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(body), filename:, content_type: 'application/octet-stream')
  end

  def gzip(body) = ActiveSupport::Gzip.compress(body)

  # A toolkit whose tools say what they were given and what they found,
  # and end as `exit` says: what the check does around SRA Toolkit,
  # without it.
  def fake_toolkit(exit: 0, say: nil)
    @work_dir.join("fake-toolkit-#{SecureRandom.hex(4)}").tap {|dir|
      dir.mkpath

      %w[latf-load vdb-validate].each do |tool|
        dir.join(tool).write(<<~SH)
          #!/bin/sh
          echo "#{tool}: $*"
          for f in "$@"; do [ -f "$f" ] && echo "file: $(basename "$f") $(wc -c < "$f")"; done
          #{"echo \"#{say}\"" if say}
          exit #{exit}
        SH

        dir.join(tool).chmod(0o755)
      end
    }
  end

  def check(files, filetype: 'fastq', platform: 'ILLUMINA', toolkit: fake_toolkit)
    DRA::ReadCheck.call(files:, filetype:, platform:, toolkit:, work_dir: @work_dir)
  end

  def leftovers = @work_dir.glob('dra-read-check-*')

  test 'fastq is handed to latf-load in order, under its own names, with the platform as D-way names it' do
    result = check([blob(gzip(READ1), 'r_1.fastq.gz'), blob(gzip(READ2), 'r_2.fastq.gz')], filetype: 'generic_fastq', platform: 'ABI_SOLID')

    assert result.ok?
    assert_match(/latf-load: --quality PHRED_33 --platform SOLID --tmpfs \S+ --cache-size 2048 -o \S+ \S+r_1\.fastq\.gz \S+r_2\.fastq\.gz/, result.output)
    assert_match "file: r_1.fastq.gz #{gzip(READ1).bytesize}", result.output
    assert_empty leftovers, 'removed once read'
  end

  # The newer platforms latf-load has no name for, it reads without one.
  test 'a platform the loader does not name is left out' do
    assert_no_match '--platform', check([blob(READ1, 'r.fastq')], platform: 'OXFORD_NANOPORE').output
  end

  test 'what the loader refuses is reported with what it said, and nothing is left behind' do
    result = check([blob(READ1, 'r.fastq')], toolkit: fake_toolkit(exit: 3, say: 'latf-load.3.4.1 err: load failed'))

    assert_not result.ok?
    assert_equal ['latf-load.3.4.1 err: load failed'], result.errors
    assert_empty leftovers
  end

  # vdb-validate passes over a file it does not recognise, silently and
  # with 0: exiting well says nothing about a file it did not name.
  test 'an sra file passes only when vdb-validate called it consistent, each by name' do
    consistent = fake_toolkit(say: "vdb-validate.3.4.1 info: Database 'a.sra' is consistent")

    assert check([blob('x', 'a.sra')], filetype: 'sra', toolkit: consistent).ok?
    assert_not check([blob('x', 'a.sra'), blob('y', 'b.sra')], filetype: 'sra', toolkit: consistent).ok?, 'b.sra was not called consistent'
    assert_not check([blob('x', 'a.sra')], filetype: 'sra', toolkit: fake_toolkit).ok?, 'silent'
  end

  test 'a filetype not read here yet is refused by name' do
    error = assert_raises(ArgumentError) { check([blob('x', 'a.bam')], filetype: 'bam') }

    assert_match 'bam files are not read here yet', error.message
  end

  # Found missing before anything is copied: a run is tens of gigabytes.
  test 'a host without SRA Toolkit says so before copying anything' do
    files = [blob(READ1, 'r.fastq')]

    files.first.stub(:download, ->(*) { flunk 'copied before the tool was looked for' }) do
      error = assert_raises(DRA::ReadCheck::ToolMissing) { check(files, toolkit: @work_dir.join('nowhere')) }

      assert_match 'latf-load is not installed here', error.message
    end
  end

  test 'a file named only dots is still copied out' do
    assert_match 'file: file ', check([blob(READ1, '..')]).output
  end

  # Left by a check whose process was killed.
  test 'a directory left by an old check is removed by the next' do
    stale = @work_dir.join('dra-read-check-stale').tap(&:mkpath)
    FileUtils.touch stale, mtime: 3.days.ago.to_time

    check([blob(READ1, 'r.fastq')])

    assert_not stale.exist?
  end
end

# SRA Toolkit itself, where it is installed (the image, and CI): what the
# check is for is what it makes of the reads.
class DRA::ReadCheckWithSRAToolkitTest < ActiveSupport::TestCase
  setup do
    skip 'SRA Toolkit is not installed' unless system('latf-load --version', out: File::NULL, err: File::NULL)

    @work_dir = Pathname.new(Dir.mktmpdir('read-check-test-'))
  end

  teardown do
    @work_dir&.rmtree
  end

  def blob(body, filename)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(body), filename:, content_type: 'application/octet-stream')
  end

  def check(files, filetype: 'fastq')
    DRA::ReadCheck.call(files:, filetype:, platform: 'ILLUMINA', work_dir: @work_dir)
  end

  test 'latf-load takes a compressed pair and refuses malformed reads' do
    taken = check([
      blob(ActiveSupport::Gzip.compress(DRA::ReadCheckTest::READ1), 'r_1.fastq.gz'),
      blob(ActiveSupport::Gzip.compress(DRA::ReadCheckTest::READ2), 'r_2.fastq.gz')
    ])

    assert taken.ok?, taken.output
    assert_empty taken.errors

    refused = check([blob(DRA::ReadCheckTest::MALFORMED, 'r.fastq')])

    assert_not refused.ok?
    assert(refused.errors.any? { it.include?('length of original quality does not match sequence') })
  end

  # A run as a mirror sends it, made here the way SRA makes one.
  test 'vdb-validate takes an sra file, and refuses one damaged or not SRA at all' do
    dir = @work_dir.join('made').tap(&:mkpath)
    dir.join('r.fastq').write(DRA::ReadCheckTest::READ1)

    assert system('latf-load', '--quality', 'PHRED_33', '-o', dir.join('db').to_s, dir.join('r.fastq').to_s, out: File::NULL, err: File::NULL)
    assert system('kar', '-c', dir.join('r.sra').to_s, '-d', dir.join('db').to_s, out: File::NULL, err: File::NULL)

    sra     = dir.join('r.sra').binread
    damaged = sra.dup.tap { it[sra.bytesize / 2, 16] = "\xFF".b * 16 }

    assert check([blob(sra, 'r.sra')], filetype: 'sra').ok?
    assert_not check([blob(damaged, 'r.sra')], filetype: 'sra').ok?, 'damaged'
    assert_not check([blob(DRA::ReadCheckTest::READ1, 'r.sra')], filetype: 'sra').ok?, 'not SRA at all'
  end
end
