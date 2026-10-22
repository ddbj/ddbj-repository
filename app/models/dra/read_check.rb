# frozen_string_literal: true

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
#     `vdb-validate`, a file at a time, which checks the file is intact —
#     each column against its md5, or its blobs' CRC where it has none. A
#     file it does not recognise it passes over without a word and exits 0,
#     so a file passes only when it said the file, by name, is consistent.
#     Intact is not readable as reads (a file without its READ column is
#     consistent), so `fastq-dump` then reads one spot of it, as the stage
#     after accessions will read all of them.
#
# BAM comes later. Which files make a run, of which filetype, in what
# order, is the caller's: D-way ran a job only for a run whose files were
# all of one filetype, in the record's order.
#
# The files are copied out (DRA::SRAToolkit) into a directory of the
# check's own under `work_dir`, which also holds the loader's own scratch
# files: its default is /tmp, the container's layer on the host's disk.
# Those need not be shared between hosts and are written in small pieces;
# should Lustre prove slow for them, the host's local SSD (/data1, once
# mounted into the VM and the container) is where they go.
# The directory is removed however the check ends; one left by a process
# that was killed is removed by a later check (STALE_AFTER).
class DRA::ReadCheck
  Result = Data.define(:ok, :output) do
    def ok? = ok

    # What the tools complained of, a line each.
    def errors = output.lines.grep(/ err: /).map(&:chomp)
  end

  Reader = Data.define(:method, :tools)

  FASTQ = Reader.new(method: :load_fastq, tools: %w[latf-load])

  FILETYPES = {
    'fastq'         => FASTQ,
    'generic_fastq' => FASTQ,
    'sra'           => Reader.new(method: :validate_sra, tools: %w[vdb-validate fastq-dump])
  }.freeze

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
  #
  # For a check that may be stopped and taken up again (CheckDRAReadsJob):
  # `dir` is a directory of the caller's, kept between attempts and removed
  # by the caller, so the files copied out before are not copied again; and
  # `interrupt` stops the tool running if it raises (DRA::SRAToolkit).
  def initialize(files:, filetype:, platform: nil, toolkit: nil, work_dir: Rails.application.config_for(:app).work_dir!, dir: nil, interrupt: nil)
    @files     = files
    @reader    = FILETYPES.fetch(filetype) { raise ArgumentError, "#{filetype} files are not read here yet" }
    @platform  = platform
    @toolkit   = toolkit
    @work_dir  = Pathname.new(work_dir)
    @dir       = dir && Pathname.new(dir)
    @interrupt = interrupt
  end

  def call
    DRA::SRAToolkit.require! @reader.tools, toolkit: @toolkit

    @work_dir.mkpath
    sweep

    return check_in(@dir.tap(&:mkpath)) if @dir

    Dir.mktmpdir('dra-read-check-', @work_dir) { check_in Pathname.new(it) }
  end

  private

  # What a reading leaves besides the copies goes before the next: the
  # loader refuses an output directory that is already there.
  def check_in(dir)
    %w[out tmp dump].each { dir.join(it).rmtree }

    @tools = DRA::SRAToolkit.new(dir:, toolkit: @toolkit, interrupt: @interrupt)
    paths  = @files.each_with_index.map {|blob, index| @tools.copy_out(blob, dir.join('in', index.to_s)) }

    ok, output = send(@reader.method, paths, dir)

    Result.new(ok:, output: output.byteslice([output.bytesize - OUTPUT_LIMIT, 0].max..).scrub)
  end

  def load_fastq(paths, dir)
    output, status = @tools.latf_load(paths, out: dir.join('out'), platform: @platform)

    [status.success?, output]
  end

  def validate_sra(paths, dir)
    outputs = paths.map {|path| validate_sra_file(path, dir) }

    [outputs.all?(&:first), outputs.map(&:last).join]
  end

  # Said of a file by name, on a line of its own: nothing else vdb-validate
  # prints for a file can match.
  def validate_sra_file(path, dir)
    name           = path.basename.to_s
    output, status = @tools.run('vdb-validate', path.to_s)
    consistent     = /^\S+ vdb-validate\.[\d.]+ info: (?:Database|Table) '#{Regexp.escape(name)}' is consistent$/

    # Silent, for a file that is not SRA at all.
    return [false, output + note(name, 'vdb-validate did not find it consistent')] unless status.success? && output.match?(consistent)

    read, status = @tools.run('fastq-dump', '-X', '1', '-O', dir.join('dump').to_s, path.to_s)

    return [false, output + read + note(name, 'fastq-dump could not read a spot of it')] unless status.success?

    [true, output]
  end

  # In the form the tools write theirs, so that Result#errors has it too.
  def note(name, text) = "read-check err: #{name}: #{text}\n"

  def sweep
    @work_dir.glob('dra-read-check-*').each do |dir|
      dir.rmtree if dir.mtime < STALE_AFTER.ago
    rescue Errno::ENOENT
      nil
    end
  end
end
