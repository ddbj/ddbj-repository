# frozen_string_literal: true

# A DRA run's reads made into what the archive publishes, once the run has
# its accession — the stage after accessions of D-way's dravalidationbatch
# (MakeKar, MakeFastq), with the same tools:
#
#   - `<run>.sra`: fastq loaded by `latf-load` (as DRA::ReadCheck loads it)
#     and packed into one file by `kar`; reads sent already as SRA are that
#     file.
#   - `<run>.fastq.bz2`, `<run>_1.fastq.bz2` …: the .sra dumped by
#     `fastq-dump --split-3 --skip-technical`, named by the run's accession,
#     and compressed by `pbzip2`.
#
# Made in `dir`, a directory of the caller's kept between attempts (the
# copies of the reads are not copied again), into its `built/`; the caller
# puts them where they go (DRA::ReadsTree).
class DRA::ReadBuild
  Result = Data.define(:ok, :output, :sra, :fastqs) do
    def ok? = ok
  end

  FASTQ = %w[latf-load kar fastq-dump].freeze

  TOOLS = {
    'fastq'         => FASTQ,
    'generic_fastq' => FASTQ,
    'sra'           => %w[fastq-dump]
  }.freeze

  COMPRESSOR = 'pbzip2'

  # Of the host the API is served from.
  COMPRESSOR_PROCESSES = 4

  def self.call(...) = new(...).call

  # As DRA::ReadCheck takes them, and the run's accession.
  def initialize(files:, filetype:, accession:, dir:, platform: nil, toolkit: nil, interrupt: nil)
    @files     = files
    @filetype  = filetype
    @tools     = TOOLS.fetch(filetype) { raise ArgumentError, "#{filetype} files are not built here yet" }
    @accession = accession
    @dir       = Pathname.new(dir)
    @platform  = platform
    @toolkit   = toolkit
    @interrupt = interrupt
  end

  def call
    DRA::SRAToolkit.require! @tools, toolkit: @toolkit
    raise DRA::SRAToolkit::ToolMissing, "#{COMPRESSOR} is not installed here" unless DRA::SRAToolkit.path(COMPRESSOR)

    @dir.mkpath
    %w[out tmp dump built].each { @dir.join(it).rmtree }
    @dir.join('built').mkpath

    @sra_toolkit = DRA::SRAToolkit.new(dir: @dir, toolkit: @toolkit, interrupt: @interrupt)
    @shell        = DRA::SRAToolkit.new(dir: @dir, interrupt: @interrupt)

    paths = @files.each_with_index.map {|blob, index| @sra_toolkit.copy_out(blob, @dir.join('in', index.to_s)) }
    sra   = @dir.join('built', "#{@accession}.sra")

    output = +''

    ok = (@filetype == 'sra' ? take_sra(paths, sra, output) : load_fastq(paths, sra, output)) && dump(sra, output) && compress(output)

    Result.new(ok:, output:, sra: (sra if ok), fastqs: ok ? @dir.join('built').glob('*.fastq.bz2').sort : [])
  end

  private

  def load_fastq(paths, sra, output)
    said, status = @sra_toolkit.latf_load(paths, out: @dir.join('out'), platform: @platform)

    output << said

    return false unless status.success?

    said, status = @sra_toolkit.run('kar', '-c', sra.to_s, '-d', @dir.join('out').to_s)

    output << said

    status.success?
  end

  # The file sent is the run, as the mirrors send it: one.
  def take_sra(paths, sra, output)
    unless paths.one?
      output << "read-build err: a run sent as SRA is one file; this one is #{paths.size}\n"

      return false
    end

    FileUtils.ln paths.first, sra

    true
  end

  def dump(sra, output)
    said, status = @sra_toolkit.run('fastq-dump', '--split-3', '--skip-technical', '-A', @accession, '-O', @dir.join('dump').to_s, sra.to_s)

    output << said

    status.success? && @dir.join('dump').glob('*.fastq').any?
  end

  # Not SRA Toolkit's: from PATH, whichever `toolkit` is.
  def compress(output)
    @dir.join('dump').glob('*.fastq').sort.all? {|fastq|
      said, status = @shell.run(COMPRESSOR, "-p#{COMPRESSOR_PROCESSES}", '-f', fastq.to_s)

      output << said

      next false unless status.success?

      @dir.join('dump', "#{fastq.basename}.bz2").rename @dir.join('built', "#{fastq.basename}.bz2")

      true
    }
  end
end
