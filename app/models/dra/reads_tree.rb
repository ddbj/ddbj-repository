# Where a DRA run's reads are, laid out as on D-way's FTP site — the same
# under the public tree (`output_dir/public/dra`, D-way's, read here) and
# the private one beside it (`output_dir/private/dra`, written here), so
# that publishing is moving one into the other (`script/dra-mover`):
#
#   fastq/DRA000/DRA000001/DRX000001/DRR000001_1.fastq.bz2
#   sra/ByExp/sra/DRX/DRX000/DRX000001/DRR000001/DRR000001.sra
class DRA::ReadsTree
  # :public or :private.
  def self.at(visibility) = new(Pathname.new(Rails.application.config_for(:app).output_dir!).join(visibility.to_s, 'dra'))

  def initialize(root)
    @root = Pathname.new(root)
  end

  attr_reader :root

  # The submission's own directory, which its public documents are in
  # too (PublicXML::DRA::Exporter).
  def submission_dir(submission) = @root.join('fastq', submission[0, 6], submission)

  def fastq_dir(submission:, experiment:) = submission_dir(submission).join(experiment)

  # An analysis's files, under their own names.
  def analysis_dir(submission:, analysis:) = submission_dir(submission).join(analysis)

  def sra_dir(experiment:, run:) = @root.join('sra', 'ByExp', 'sra', experiment[0, 3], experiment[0, 6], experiment, run)

  def sra(experiment:, run:) = sra_dir(experiment:, run:).join("#{run}.sra")

  # The run's fastq files: one, or a pair, or more for reads in several
  # segments (fastq-dump --split-3).
  def fastqs(submission:, experiment:, run:) = fastq_dir(submission:, experiment:).glob("#{run}{,_*}.fastq.bz2").sort

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
