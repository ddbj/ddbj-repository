# frozen_string_literal: true

require 'open3'

# Whether a DRA run's reads can be read the way the archive will read
# them: SRA Toolkit is given them, and either takes them or says why not.
# The check before accessions are issued — what the tools make of them is
# thrown away, and read again once they are (the two stages of D-way's
# dravalidationbatch, kept apart for the same reason: nothing to keep, or
# to clear up, while a submission waits days for its numbers).
#
# By the run's filetype, as D-way chose its job:
#
#   - fastq, generic_fastq: `latf-load`, over the run's files at once —
#     compressed or not, one file or a pair. Taken or not is the loader's
#     verdict, as it was D-way's, and the loader takes a load that drops
#     up to 5% of its records as bad; those it names in its output
#     (Result#errors), so a pass can still carry them.
#   - sra (runs sent already in SRA's format, as the mirrors send them):
#     `vdb-validate`, a file at a time, which checks every column against
#     its checksum. A file it does not recognise it passes over without a
#     word and exits 0, so a file passes only when it said the file, by
#     name, is consistent.
#
# BAM comes later. Which files make a run, of which filetype, in what
# order, is the caller's: D-way ran a job only for a run whose files were
# all of one filetype, in the record's order.
#
# The tools read files, not the store, so each file is copied out first —
# in ranges, never one GET (see MultipartUpload in CLAUDE.md) — into a
# directory of the check's own under `work_dir`, which also holds the
# loader's own scratch files: its default is /tmp, the container's layer on
# the host's disk. Those need not be shared between hosts and are written
# in small pieces; should Lustre prove slow for them, the host's local SSD
# (/data1, once mounted into the VM and the container) is where they go.
# The directory is removed however the check ends; one left by a process
# that was killed is removed by a later check (STALE_AFTER).
class DRA::ReadCheck
  Result = Data.define(:ok, :output) do
    def ok? = ok

    # What the tools complained of, a line each.
    def errors = output.lines.grep(/ err: /).map(&:chomp)
  end

  class ToolMissing < StandardError; end
  class TimedOut < StandardError; end

  FILETYPES = {
    'fastq'         => :load_fastq,
    'generic_fastq' => :load_fastq,
    'sra'           => :validate_sra
  }.freeze

  # The platforms `latf-load` is told by name, as D-way tells it
  # (dravalidationbatch Latf2sra.Platform). The rest it reads without one.
  PLATFORMS = {
    'LS454'             => 'LS454',
    'ILLUMINA'          => 'ILLUMINA',
    'HELICOS'           => 'HELICOS',
    'ABI_SOLID'         => 'SOLID',
    'COMPLETE_GENOMICS' => 'COMPLETE_GENOMICS',
    'PACBIO_SMRT'       => 'PACBIO',
    'ION_TORRENT'       => 'IONTORRENT',
    'CAPILLARY'         => 'CAPILLARY'
  }.freeze

  # What the loader holds in memory before it writes to scratch files. Its
  # default is 10 GB, for each of the checks running at once on the host
  # that serves the API; D-way gave each of its loads 4 GB.
  CACHE_MB = 2048

  # A run of hundreds of gigabytes is read in hours. Past this, something
  # other than its size is wrong.
  TIMEOUT = 12.hours

  # Older than any check still running.
  STALE_AFTER = 2.days

  # What the tools say is kept to its end: a file read wrong is reported
  # once per bad record, and the last of it says how the reading ended.
  OUTPUT_LIMIT = 64.kilobytes

  def self.call(...) = new(...).call

  # `files` are the run's blobs, in the record's order; `filetype` and
  # `platform` are the record's, as SRA spells them (fastq, sra; ILLUMINA,
  # ABI_SOLID, …). `toolkit` is where SRA Toolkit's binaries are, or nil
  # for PATH.
  def initialize(files:, filetype:, platform: nil, toolkit: nil, work_dir: Rails.application.config_for(:app).work_dir!)
    @files    = files
    @reader   = FILETYPES.fetch(filetype) { raise ArgumentError, "#{filetype} files are not read here yet" }
    @platform = platform
    @toolkit  = toolkit
    @work_dir = Pathname.new(work_dir)
  end

  def call
    tool = @reader == :load_fastq ? 'latf-load' : 'vdb-validate'

    raise ToolMissing, "#{tool} is not installed here (SRA Toolkit)" unless tool_path(tool)

    @work_dir.mkpath
    sweep

    Dir.mktmpdir('dra-read-check-', @work_dir) do |dir|
      dir   = Pathname.new(dir)
      paths = @files.each_with_index.map {|blob, index| copy_out(blob, dir.join('in', index.to_s)) }

      ok, output = send(@reader, paths, dir)

      Result.new(ok:, output: output.byteslice([output.bytesize - OUTPUT_LIMIT, 0].max..).scrub)
    end
  end

  private

  def load_fastq(paths, dir)
    dir.join('tmp').mkpath

    output, status = run(
      'latf-load',
      '--quality', 'PHRED_33', *platform_args,
      '--tmpfs', dir.join('tmp').to_s,
      '--cache-size', CACHE_MB.to_s,
      '-o', dir.join('out').to_s,
      *paths.map(&:to_s),
      chdir: dir
    )

    [status.success?, output]
  end

  def validate_sra(paths, dir)
    outputs = paths.map {|path|
      output, status = run('vdb-validate', path.to_s, chdir: dir)

      [status.success? && output.include?("'#{path.basename}' is consistent"), output]
    }

    [outputs.all?(&:first), outputs.map(&:last).join]
  end

  def platform_args
    name = PLATFORMS[@platform.to_s.upcase]

    name ? ['--platform', name] : []
  end

  def tool_path(tool)
    dirs = @toolkit ? [@toolkit.to_s] : ENV.fetch('PATH', '').split(File::PATH_SEPARATOR)

    dirs.map { File.join(it, tool) }.find { File.executable?(it) }
  end

  # Under its own name, in a directory of its own: the loader tells a
  # compressed file by its extension, vdb-validate names a file by it, and
  # two files of a run may share a name. A name that is only dots is no
  # file's.
  def copy_out(blob, dir)
    dir.mkpath

    name = blob.filename.sanitized
    name = 'file' if name.delete('.').empty?

    dir.join(name).tap {|path|
      path.open('wb') {|file| blob.download { file.write it } }
    }
  end

  # In a process group of its own, so that past TIMEOUT whatever the tool
  # started goes with it.
  def run(tool, *args, chdir:)
    Open3.popen2e(tool_path(tool), *args, chdir: chdir.to_s, pgroup: true) do |stdin, out, wait|
      stdin.close

      reader = Thread.new { out.read }

      unless wait.join(TIMEOUT)
        begin
          Process.kill('KILL', -wait.pid)
        rescue Errno::ESRCH
          nil
        end

        wait.join

        raise TimedOut, "#{tool} had not finished within #{TIMEOUT.inspect}"
      end

      [reader.value, wait.value]
    end
  end

  def sweep
    @work_dir.glob('dra-read-check-*').each do |dir|
      dir.rmtree if dir.mtime < STALE_AFTER.ago
    rescue Errno::ENOENT
      nil
    end
  end
end
