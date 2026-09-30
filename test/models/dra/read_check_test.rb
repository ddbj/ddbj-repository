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

  # A loader that says what it was given and what it found, and ends as
  # `exit` says: what the check does around the loader, without SRA
  # Toolkit.
  def fake_loader(exit: 0, say: nil)
    @work_dir.join("fake-latf-load-#{SecureRandom.hex(4)}").tap {|path|
      path.write(<<~SH)
        #!/bin/sh
        echo "args: $*"
        for f in "$@"; do [ -f "$f" ] && echo "file: $(basename "$f") $(wc -c < "$f")"; done
        #{"echo '#{say}'" if say}
        exit #{exit}
      SH
      path.chmod(0o755)
    }.to_s
  end

  def check(files, platform: 'ILLUMINA', loader: fake_loader)
    DRA::ReadCheck.call(files:, platform:, loader:, work_dir: @work_dir)
  end

  def leftovers = @work_dir.glob('dra-read-check-*')

  test 'the reads are handed to the loader in order, under their own names, with the platform as D-way names it' do
    result = check([blob(gzip(READ1), 'r_1.fastq.gz'), blob(gzip(READ2), 'r_2.fastq.gz')], platform: 'ABI_SOLID')

    assert result.ok?
    assert_match(/--quality PHRED_33 --platform SOLID --tmpfs \S+ --cache-size 2048 -o \S+ \S+r_1\.fastq\.gz \S+r_2\.fastq\.gz/, result.output)
    assert_match "file: r_1.fastq.gz #{gzip(READ1).bytesize}", result.output
    assert_empty leftovers, 'removed once read'
  end

  # The newer platforms latf-load has no name for, it reads without one.
  test 'a platform the loader does not name is left out' do
    assert_no_match '--platform', check([blob(READ1, 'r.fastq')], platform: 'OXFORD_NANOPORE').output
  end

  test 'what the loader refuses is reported with what it said, and nothing is left behind' do
    result = check([blob(READ1, 'r.fastq')], loader: fake_loader(exit: 3, say: 'latf-load.3.4.1 err: load failed'))

    assert_not result.ok?
    assert_equal ['latf-load.3.4.1 err: load failed'], result.errors
    assert_empty leftovers
  end

  # Found missing before anything is copied: a run is tens of gigabytes.
  test 'a host without SRA Toolkit says so before copying anything' do
    files = [blob(READ1, 'r.fastq')]

    files.first.stub(:download, ->(*) { flunk 'copied before the loader was looked for' }) do
      error = assert_raises(DRA::ReadCheck::LoaderMissing) { check(files, loader: 'no-such-latf-load') }

      assert_match 'no-such-latf-load is not installed here', error.message
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

  # The loader itself, where SRA Toolkit is installed (the image, and CI):
  # what the check is for is what latf-load makes of the reads.
  test 'latf-load takes a compressed pair and refuses malformed reads' do
    skip 'SRA Toolkit is not installed' unless system('latf-load --version', out: File::NULL, err: File::NULL)

    taken = check([blob(gzip(READ1), 'r_1.fastq.gz'), blob(gzip(READ2), 'r_2.fastq.gz')], loader: 'latf-load')

    assert taken.ok?, taken.output
    assert_empty taken.errors

    refused = check([blob(MALFORMED, 'r.fastq')], loader: 'latf-load')

    assert_not refused.ok?
    assert(refused.errors.any? { it.include?('length of original quality does not match sequence') })
  end
end
