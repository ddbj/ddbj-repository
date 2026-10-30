# Where a DRA submission's reads are, laid out as on D-way's FTP site — the
# same under the public trees (`output_dir/public/…`, D-way's, read here)
# and the private ones beside them (`output_dir/private/…`, written here),
# so that publishing is moving one into the other (`script/dra-mover`).
# Two trees, as the FTP site has them, each on a filesystem of its own:
#
#   dra/fastq/DRA000/DRA000001/DRX000001/DRR000001_1.fastq.bz2
#   dra/sra/ByExp/sra/DRX/DRX000/DRX000001/DRR000001/DRR000001.sra
#   sra/DRR/000/000/001/DRR000001/submitted/reads_1.fq.gz
#
# the second the runs' files as they were sent (`/public/sra/DRR` on the
# FTP site), which D-way publishes for every run since V3.26.
class DRA::ReadsTree
  # :public or :private.
  def self.at(visibility)
    dir = Pathname.new(Rails.application.config_for(:app).output_dir!).join(visibility.to_s)

    new(dra: dir.join('dra'), sra: dir.join('sra'))
  end

  def initialize(dra:, sra:)
    @roots = {dra: Pathname.new(dra), sra: Pathname.new(sra)}
  end

  attr_reader :roots

  # The submission's own directory, which its public documents are in
  # too (PublicXML::DRA::Exporter).
  def submission_dir(submission) = @roots[:dra].join('fastq', submission[0, 6], submission)

  def fastq_dir(submission:, experiment:) = submission_dir(submission).join(experiment)

  # An analysis's files, under their own names.
  def analysis_dir(submission:, analysis:) = submission_dir(submission).join(analysis)

  def sra_dir(experiment:, run:) = @roots[:dra].join('sra', 'ByExp', 'sra', experiment[0, 3], experiment[0, 6], experiment, run)

  def sra(experiment:, run:) = sra_dir(experiment:, run:).join("#{run}.sra")

  # A run's files as sent, under their own names: by the run's number in
  # nine digits, three a directory, as D-way's release files them.
  def submitted_dir(run:)
    digits = format('%09d', run.delete_prefix('DRR').to_i)

    @roots[:sra].join('DRR', digits[0, 3], digits[3, 3], digits[6, 3], run, 'submitted')
  end

  # The run's fastq files: one, or a pair, or more for reads in several
  # segments (fastq-dump --split-3).
  def fastqs(submission:, experiment:, run:) = fastq_dir(submission:, experiment:).glob("#{run}{,_*}.fastq.bz2").sort

  # The tree `path` is in, by name, and where in it — as a move names it.
  def locate(path)
    name, root = @roots.find {|_, root| path.to_s.start_with?("#{root}/") }

    raise ArgumentError, "#{path} is in none of the trees" unless name

    [name, path.relative_path_from(root)]
  end

  # As the mover takes a file public: writable by its owner alone.
  FILE_MODE = 0o644

  # `file` put at `path`, renamed where it can be — the same mount — and
  # otherwise copied beside it and renamed, then removed: a move stopped
  # part way leaves `file` where it was, and a copy under a name nothing
  # reads.
  def self.move(file, path)
    path.dirname.mkpath
    file.chmod FILE_MODE
    file.rename path
  rescue Errno::EXDEV
    partial = path.sub_ext("#{path.extname}.partial")

    FileUtils.cp file, partial
    partial.chmod FILE_MODE
    partial.rename path
    file.delete
  end
end
