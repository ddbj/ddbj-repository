require 'test_helper'

class DRA::ReadCheckTest < ActiveSupport::TestCase
  FASTQ     = "@r1\nACGTACGTAC\n+\nIIIIIIIIII\n@r2\nTTTTGGGGCC\n+\nIIIIIIIIII\n"
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

  # A loader that says what it was given and what it found, and ends as
  # `exit` says: what the check does around the loader, without SRA
  # Toolkit.
  def fake_loader(exit: 0)
    @work_dir.join('fake-latf-load').tap {|path|
      path.write(<<~SH)
        #!/bin/sh
        echo "args: $*"
        for f in "$@"; do [ -f "$f" ] && echo "file: $(basename "$f") $(wc -c < "$f")"; done
        exit #{exit}
      SH
      path.chmod(0o755)
    }.to_s
  end

  def check(files, platform: 'ILLUMINA', loader: fake_loader)
    DRA::ReadCheck.call(files:, platform:, loader:, work_dir: @work_dir)
  end

  test 'the reads are handed to the loader under their own names, with the platform as D-way names it' do
    result = check([blob(FASTQ, 'r_1.fastq.gz'), blob(FASTQ, 'r_2.fastq.gz')], platform: 'ABI_SOLID')

    assert result.ok?
    assert_match '--platform SOLID --quality PHRED_33 -o ', result.output
    assert_match "file: r_1.fastq.gz #{FASTQ.bytesize}", result.output
    assert_match "file: r_2.fastq.gz #{FASTQ.bytesize}", result.output
  end

  # The newer platforms latf-load has no name for, it reads without one.
  test 'a platform the loader does not name is left out' do
    assert_no_match '--platform', check([blob(FASTQ, 'r.fastq')], platform: 'OXFORD_NANOPORE').output
  end

  test 'what the loader refuses is reported with what it said, and nothing is left behind' do
    result = check([blob(FASTQ, 'r.fastq')], loader: fake_loader(exit: 3))

    assert_not result.ok?
    assert_match 'args:', result.output
    assert_empty @work_dir.glob('dra-read-check-*')
  end

  test 'a host without SRA Toolkit says so' do
    error = assert_raises(DRA::ReadCheck::LoaderMissing) { check([blob(FASTQ, 'r.fastq')], loader: 'no-such-latf-load') }

    assert_match 'no-such-latf-load is not installed here', error.message
    assert_empty @work_dir.glob('dra-read-check-*')
  end

  # The loader itself, where SRA Toolkit is installed (the image, and CI):
  # what the check is for is what latf-load makes of the reads.
  test 'latf-load takes well-formed reads and refuses malformed ones' do
    skip 'SRA Toolkit is not installed' unless system('latf-load --version', out: File::NULL, err: File::NULL)

    assert check([blob(FASTQ, 'r.fastq')], loader: 'latf-load').ok?

    refused = check([blob(MALFORMED, 'r.fastq')], loader: 'latf-load')

    assert_not refused.ok?
    assert_match 'length of original quality does not match sequence', refused.output
  end
end
