# frozen_string_literal: true

require 'open3'

# SRA Toolkit, run over files copied out of the store into a directory of
# a caller's own — what DRA::ReadCheck reads reads with, and DRA::ReadBuild
# makes the archive's files with.
#
# The tools read files, not the store, so each file is copied out first —
# in ranges, never one GET (see MultipartUpload in CLAUDE.md). The
# directory also holds what the tools write, their settings and their
# HOME: they are told to ask nothing of NCBI's servers (an aligned file
# sends vdb-validate looking for its references online, a minute a file
# where the host cannot reach them), and fastq-dump leaves its error
# reports in HOME.
#
# `interrupt` is called while copying and while a tool runs, and stops the
# tool if it raises — how a job stopped by a deploy stops what it started.
class DRA::SRAToolkit
  class ToolMissing < StandardError; end
  class TimedOut < StandardError; end

  # Longer than this, a file's name is cut (keeping its extension) to fit
  # a filesystem's 255.
  NAME_BYTES = 200

  # A run of hundreds of gigabytes is read in hours. Past this, something
  # other than its size is wrong.
  TIMEOUT = 12.hours

  # How often a running tool is looked in on, to be stopped if `interrupt`
  # says so.
  INTERRUPT_EVERY = 5.seconds

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
  # default is 10 GB, for each of the loads running at once on the host
  # that serves the API; D-way gave each of its loads 4 GB.
  CACHE_MB = 2048

  def self.require!(tools, toolkit: nil)
    tools.each do |tool|
      raise ToolMissing, "#{tool} is not installed here (SRA Toolkit)" unless path(tool, toolkit:)
    end
  end

  def self.path(tool, toolkit: nil)
    dirs = toolkit ? [toolkit.to_s] : ENV.fetch('PATH', '').split(File::PATH_SEPARATOR)

    dirs.map { File.join(it, tool) }.find { File.executable?(it) }
  end

  # `toolkit` is where SRA Toolkit's binaries are, or nil for PATH.
  def initialize(dir:, toolkit: nil, interrupt: nil)
    @dir       = Pathname.new(dir)
    @toolkit   = toolkit
    @interrupt = interrupt
  end

  attr_reader :dir

  # Under its own name, in a directory of its own: the loader tells a
  # compressed file by its extension, vdb-validate names a file by it, and
  # two files of a run may share a name. A name that is only dots is no
  # file's.
  def copy_out(blob, dir)
    dir.mkpath

    name = blob.filename.sanitized
    name = 'file' if name.delete('.').empty?
    name = shorten(name) if name.bytesize > NAME_BYTES

    dir.join(name).tap {|path|
      # Copied before, by an attempt that was stopped later.
      next if path.exist? && path.size == blob.byte_size

      path.open('wb') {|file|
        blob.download do |chunk|
          file.write chunk
          @interrupt&.call
        end
      }
    }
  end

  # The tool's output, stdout and stderr together, and its status. In a
  # process group of its own, so that past TIMEOUT whatever the tool
  # started goes with it.
  def run(tool, *args)
    settings = @dir.join('ncbi.mkfg')
    settings.write(%(/repository/remote/disabled = "true"\n)) unless settings.exist?

    env = {'NCBI_SETTINGS' => settings.to_s, 'HOME' => @dir.to_s}

    Open3.popen2e(env, self.class.path(tool, toolkit: @toolkit), *args, chdir: @dir.to_s, pgroup: true) do |stdin, out, wait|
      stdin.close

      # Stopped early, the tool's output is closed under it; that is no news.
      reader   = Thread.new { out.read }.tap { it.report_on_exception = false }
      deadline = TIMEOUT.from_now

      until wait.join(INTERRUPT_EVERY)
        if Time.current > deadline
          stop wait

          raise TimedOut, "#{tool} had not finished within #{TIMEOUT.inspect}"
        end

        begin
          @interrupt&.call
        rescue Exception # rubocop:disable Lint/RescueException
          stop wait

          raise
        end
      end

      [reader.value, wait.value]
    end
  end

  # fastq loaded into an SRA database at `out`, as D-way loaded it: its
  # qualities as Phred+33, its platform named where latf-load names it, its
  # scratch files beside it rather than in the container's /tmp.
  def latf_load(paths, out:, platform: nil)
    tmp  = @dir.join('tmp').tap(&:mkpath)
    name = PLATFORMS[platform.to_s.upcase]

    run(
      'latf-load',
      '--quality', 'PHRED_33', *(['--platform', name] if name),
      '--tmpfs', tmp.to_s,
      '--cache-size', CACHE_MB.to_s,
      '-o', out.to_s,
      *paths.map(&:to_s)
    )
  end

  private

  def shorten(name)
    extension = name[/(?:\.[^.]{1,10}){0,2}\z/]

    name.byteslice(0, NAME_BYTES - extension.bytesize).scrub('') + extension
  end

  def stop(wait)
    Process.kill('KILL', -wait.pid)
  rescue Errno::ESRCH
    nil
  ensure
    wait.join
  end
end
