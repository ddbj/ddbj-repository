# frozen_string_literal: true

require 'open3'

# Whether a DRA run's reads can be read the way the archive will read
# them: SRA Toolkit's loader is given them, and either takes them or says
# why not. The check before accessions are issued — what the loader makes
# of them is thrown away, and read again once they are (the two stages of
# D-way's dravalidationbatch, kept apart for the same reason: nothing to
# keep, or to clear up, while a submission waits days for its numbers).
#
# fastq, compressed or not, one file or a pair, is read by `latf-load`,
# as D-way reads both `fastq` and `generic_fastq`. BAM and runs sent
# already in SRA's format are read by other tools, and come later.
#
# The loader reads files, not the store, so each file is copied out first
# — in ranges, never one GET (see MultipartUpload in CLAUDE.md) — into a
# directory of the check's own under `work_dir`, removed however the check
# ends.
class DRA::ReadCheck
  Result = Data.define(:ok, :output) do
    def ok? = ok
  end

  class LoaderMissing < StandardError; end

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

  # What the loader says is kept to its end: a file read wrong is reported
  # once per bad record, and the last of it says how the load ended.
  OUTPUT_LIMIT = 64.kilobytes

  def self.call(...) = new(...).call

  # `files` are the run's blobs; `platform` is the record's, as SRA
  # spells it (ILLUMINA, ABI_SOLID, …).
  def initialize(files:, platform:, loader: 'latf-load', work_dir: Rails.application.config_for(:app).work_dir!)
    @files    = files
    @platform = platform
    @loader   = loader
    @work_dir = Pathname.new(work_dir)
  end

  def call
    @work_dir.mkpath

    Dir.mktmpdir('dra-read-check-', @work_dir) do |dir|
      paths = @files.each_with_index.map {|blob, index| copy_out(blob, Pathname.new(dir).join('in', index.to_s)) }

      output, status = Open3.capture2e(@loader, *platform_args, '--quality', 'PHRED_33', '-o', File.join(dir, 'out'), *paths.map(&:to_s), chdir: dir)

      Result.new(ok: status.success?, output: output.byteslice([output.bytesize - OUTPUT_LIMIT, 0].max..).scrub)
    end
  rescue Errno::ENOENT => e
    raise unless e.message.include?(@loader)

    raise LoaderMissing, "#{@loader} is not installed here (SRA Toolkit)"
  end

  private

  def platform_args
    name = PLATFORMS[@platform.to_s.upcase]

    name ? ['--platform', name] : []
  end

  # Under its own name, in a directory of its own: the loader tells a
  # compressed file by its extension, and two runs' files may share one.
  def copy_out(blob, dir)
    dir.mkpath

    dir.join(blob.filename.sanitized).tap {|path|
      path.open('wb') {|file| blob.download { file.write it } }
    }
  end
end
