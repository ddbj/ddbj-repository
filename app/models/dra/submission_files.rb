# A DRA submission's files in a tree (DRA::ReadsTree): what is in its
# directory there besides its documents — its experiments' fastq, its
# analyses' files (DRX…/, DRZ…/) — its runs' .sra, and their files as sent
# (…/DRR…/submitted/). Asked to be moved
# between the private tree and the public one as it is published and
# withdrawn (PublicXML::DRA::Exporter), D-way's among them: found where
# they are, not where they were built.
#
# Only what is the submission's by name, and never through a link: the
# public tree is shared with the mirror, and a link in it leads anywhere.
# Not what a copy stopped part way left either (`.partial`), which is not
# a file of anyone's.
class DRA::SubmissionFiles
  # An experiment, run or analysis of DRA's, as the mover takes them.
  OBJECT_FORMAT = /\ADR[XRZ]\d{6,}\z/
  RUN_FORMAT    = /\ADRR\d{6,}\z/

  def initialize(accession, record)
    @accession = accession
    @record    = record
  end

  # Its runs' .sra first, then their files as sent, then what is in its
  # directory.
  def at(tree)
    directory = tree.submission_dir(@accession)

    objects = real_directory?(directory) ? directory.children.select { real_directory?(it) && it.basename.to_s.match?(OBJECT_FORMAT) } : []
    within  = objects.flat_map { walk(it) }

    sras      = runs.flat_map {|run, experiment| experiment ? files_in(tree.sra_dir(experiment:, run:)) : [] }
    submitted = runs.flat_map {|run, _| files_in(tree.submitted_dir(run:)) }

    (sras + submitted + within).reject { it.extname == '.partial' }
  end

  # The runs whose .sra is in neither tree, or that are filed under no
  # experiment: built here, every run has one.
  def missing_sras(*trees)
    runs.filter_map {|run, experiment|
      run unless experiment && trees.any? { it.sra(experiment:, run:).file? }
    }
  end

  private

  def files_in(dir) = real_directory?(dir) ? dir.children.select { regular_file?(it) } : []

  # Not through a link.
  def walk(dir) = dir.children.flat_map { real_directory?(it) ? walk(it) : (regular_file?(it) ? [it] : []) }

  def real_directory?(path) = lstat(path)&.directory?
  def regular_file?(path)   = lstat(path)&.file?

  def lstat(path)
    File.lstat(path)
  rescue Errno::ENOENT
    nil
  end

  # [run, experiment] for each run with a run's accession; the experiment nil
  # where it is not one.
  def runs
    @runs ||= DRA::RecordRuns.new(@record).filter_map {|run|
      next unless run.accession.to_s.match?(RUN_FORMAT)

      experiment = run.experiment&.dig('accession')

      [run.accession, (experiment if experiment.to_s.match?(OBJECT_FORMAT))]
    }
  end
end
