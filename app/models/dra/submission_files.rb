# A DRA submission's files in a tree (DRA::ReadsTree): what is in its
# directory there besides its documents — its experiments' fastq, its
# analyses' files (DRX…/, DRZ…/) — and its runs' .sra. Moved between the
# private tree and the public one as it is published and withdrawn, D-way's
# among them: found where they are, not where they were built.
#
# Only what is the submission's by name, and never through a link: the
# public tree is shared with the mirror, and a link in it leads anywhere.
class DRA::SubmissionFiles
  # An experiment, run or analysis of DRA's — or of the 27 numbered SRA.
  OBJECT_FORMAT = /\A[DS]R[XRZ]\d{6,}\z/

  def initialize(accession, record)
    @accession = accession
    @record    = record
  end

  # Each moved alone, so a move stopped part way is gone on from by the
  # next: what has gone across is no longer in `from`. What a move stopped
  # while copying left (DRA::ReadsTree.move) goes first, from both: in the
  # public tree it would be served.
  #
  # The directories it leaves empty in `from` go, up to the submission's
  # own and the .sra's root: those are shared, with the documents and with
  # the mirror's — and the submission's own too, once nothing is in it.
  def move(from:, to:)
    [from, to].each { files(it, partial: true).each(&:delete) }

    stops = [from.submission_dir(@accession), from.root.join('sra', 'ByExp', 'sra')]

    paths(from).each do |path|
      DRA::ReadsTree.move from.root.join(path), to.root.join(path)

      prune from.root.join(path).dirname, stops, from.root
    end

    prune from.submission_dir(@accession), [from.root.join('fastq')], from.root
  end

  # Relative to the tree's root.
  def paths(tree) = files(tree).map { it.relative_path_from(tree.root) }

  # The runs whose .sra is in neither tree, or that are filed under no
  # experiment: built here, every run has one.
  def missing_sras(*trees)
    runs.filter_map {|run, experiment|
      run unless experiment && trees.any? { it.sra(experiment:, run:).file? }
    }
  end

  private

  # The files, or what a move stopped while copying left of them.
  def files(tree, partial: false)
    directory = tree.submission_dir(@accession)

    objects = (directory.directory? && !directory.symlink?) ? directory.children.select { real_directory?(it) && it.basename.to_s.match?(OBJECT_FORMAT) } : []
    within  = objects.flat_map { walk(it) }

    sras = runs.filter_map {|run, experiment|
      dir = tree.sra_dir(experiment:, run:) if experiment

      dir.children.select { regular_file?(it) } if dir && real_directory?(dir)
    }.flatten

    (within + sras).select { (it.extname == '.partial') == partial }
  end

  # Not through a link.
  def walk(dir) = dir.children.flat_map { real_directory?(it) ? walk(it) : (regular_file?(it) ? [it] : []) }

  def real_directory?(path) = lstat(path)&.directory?
  def regular_file?(path)   = lstat(path)&.file?

  def lstat(path)
    File.lstat(path)
  rescue Errno::ENOENT
    nil
  end

  # [run, experiment] for each run with an accession; the experiment nil
  # where it is not one.
  def runs
    @runs ||= DRA::RecordRuns.new(@record).filter_map {|run|
      next unless run.accession.to_s.match?(OBJECT_FORMAT)

      experiment = run.experiment&.dig('accession')

      [run.accession, (experiment if experiment.to_s.match?(OBJECT_FORMAT))]
    }
  end

  def prune(dir, stops, root)
    until stops.include?(dir) || !dir.to_s.start_with?("#{root}/")
      dir.rmdir
      dir = dir.dirname
    end
  rescue Errno::ENOTEMPTY, Errno::ENOENT, Errno::ENOTDIR
    nil
  end
end
