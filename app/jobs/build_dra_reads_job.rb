# A DRA submission's reads made into what the archive publishes, once its
# accessions are issued (DRA::ReadBuild): each run's `.sra` and fastq, and
# each analysis's files as sent, put into the private tree (DRA::ReadsTree),
# from where its publication has them moved into the public one
# (PublicXML::DRA::Exporter). Then it is built (`reads_built_at`), and an
# accession-issued one is private — as D-way's batch moved a submission
# from accession issued to private once its fastq were made. One a curator
# made private before is built all the same.
#
# Only one sent here: D-way's were built by D-way.
#
# Started by `enqueue_due` (every ten minutes) for each submission waiting
# for it with no job of its own, rather than by the issuance: a job lost
# between the issuing commit and its enqueue would otherwise leave the
# submission waiting with nothing to finish it. One that failed is left
# for a person (Mission Control): reads the loader takes at the check and
# not after, or of a filetype not built here, are not mended by trying
# again. Retried there, it goes on; discarded, the next sweep starts it
# again.
#
# One at a time, and in turn with the checks (DRA_READS): the same tools
# over the same reads, for hours. One run of a submission at once
# (AdvisoryLock): RecoverKilledJobsJob may start one while the one it
# replaces is alive yet, and two would build into one directory. Taken up
# again where it was stopped: a run whose `.sra` is in the tree is not
# built again — it goes in last — and the run it was in keeps the reads it
# had copied out, in a directory of the submission's own under `work_dir`.
class BuildDRAReadsJob < ApplicationJob
  include ActiveJob::Continuable

  class Failed < StandardError; end

  queue_with_priority 10

  self.max_resumptions = CheckDRAReadsJob::MAX_RESUMPTIONS
  self.resume_options  = {wait: 5.seconds, priority: 0}
  limits_concurrency(**CheckDRAReadsJob::DRA_READS)

  discard_on ActiveJob::DeserializationError
  retry_on AdvisoryLock::Held, wait: 1.minute, attempts: :unlimited

  KEPT_PREFIX = 'dra-build-'

  def self.waiting
    DRASubmission.where(status: %i[accession_issued private], reads_built_at: nil).where.not(accession: nil).joins(:submission).where(submissions: {source_id: nil})
  end

  # The copies kept for a submission with no job go first: one started
  # here may be copying into its own already.
  def self.enqueue_due
    queued   = self.queued
    building = queued.filter_map { GlobalID.parse(it)&.model_id }.to_set

    kept_dir('*').dirname.glob("#{KEPT_PREFIX}*").each do |dir|
      dir.rmtree unless building.include?(dir.basename.to_s.delete_prefix(KEPT_PREFIX))
    end

    waiting.includes(:submission).find_each do |row|
      perform_later row.submission unless queued.include?(row.submission.to_global_id.to_s)
    end
  end

  # The submissions every job not finished is for, failed or not, as
  # global ids (see DDBJValidatorCheck.live_readings).
  def self.queued
    SolidQueue::Job.where(class_name: name, finished_at: nil).pluck(:arguments).filter_map {
      it.dig('arguments', 0, '_aj_globalid') if it.is_a?(Hash)
    }.to_set
  end

  def self.analysis_file_name(entry) = ActiveStorage::Filename.new(File.basename(entry.filename)).sanitized

  def self.kept_dir(submission_id) = Pathname.new(Rails.application.config_for(:app).work_dir!).join("#{KEPT_PREFIX}#{submission_id}")

  def perform(submission)
    AdvisoryLock.exclusively("build_dra_reads:#{submission.id}") { build_all submission }
  end

  private

  def build_all(submission)
    row = self.class.waiting.find_by(submission:) or return

    record = submission.materialised_record
    files  = DRA::RecordFiles.new(record, submission.data_files.blobs)

    if (gone = files.unmatched).any?
      raise Failed, "#{row.accession}: #{gone.map { "#{it.where} #{it.problem}" }.join('; ')}"
    end

    runs     = DRA::RecordRuns.new(record, files).to_a
    analyses = files.entries.select { it.list == 'analyses' }

    analyses.group_by { [it.index, self.class.analysis_file_name(it)] }.each do |(_, name), entries|
      raise Failed, "#{row.accession}: #{entries.first.where} names two files #{name}" if entries.size > 1
    end

    step :build do |step|
      runs.each do |run|
        build row, run, interrupt: -> { step.checkpoint! }
      end

      analyses.each do |entry|
        place row, entry, interrupt: -> { step.checkpoint! }
      end

      clear_analyses row, analyses
    end

    # Built, whatever its status has become meanwhile.
    Submission.transaction do
      DRASubmission.where(id: row.id, reads_built_at: nil).update_all reads_built_at: Time.current

      count = DRASubmission.status_accession_issued.where(id: row.id).move_to_status!('private')

      if count.positive?
        CurationEvent.record!(
          submission:,
          actor:      'system:reads built',
          action:     :curation_updated,
          row_count:  count,
          noun:       submission.curation_row_noun,
          status:     'private'
        )
      end
    end

    self.class.kept_dir(submission.id).rmtree
  end

  def build(row, run, interrupt:)
    raise Failed, "#{row.accession}: #{run.where} has no accession" unless run.accession.to_s.match?(DRA::SubmissionFiles::OBJECT_FORMAT)

    raise Failed, "#{row.accession}: #{run.where} is part of #{run.experiments.size} experiments; a run is filed under one" unless run.experiments.size <= 1

    experiment = run.experiment&.dig('accession').to_s

    raise Failed, "#{row.accession}: #{run.where} is part of no experiment with an accession" unless experiment.match?(DRA::SubmissionFiles::OBJECT_FORMAT)
    tree       = DRA::ReadsTree.at(:private)

    # In the tree already, from an attempt stopped after it.
    return if tree.sra(experiment:, run: run.accession).exist?

    filetypes = run.filetypes

    raise Failed, "#{row.accession}: #{run.where} names no files" if run.entries.empty?
    raise Failed, "#{row.accession}: #{run.where} has files of #{filetypes.join(', ')}; a run is built from one filetype" unless filetypes.one?
    raise Failed, "#{row.accession}: #{run.where} is of #{filetypes.first} files, which are not built here yet" unless DRA::ReadBuild::TOOLS.key?(filetypes.first)

    dir    = self.class.kept_dir(row.submission_id).join("run-#{run.index}")
    result = DRA::ReadBuild.call(files: run.entries.map(&:blob), filetype: filetypes.first, accession: run.accession, platform: run.platform, dir:, interrupt:)

    raise Failed, "#{row.accession}: #{run.where} (#{run.accession}) could not be built:\n#{result.output.lines.last(10).join}" unless result.ok?

    fastq_dir = tree.fastq_dir(submission: row.accession, experiment:)

    # What an earlier build of it left, of another shape or half moved.
    (tree.fastqs(submission: row.accession, experiment:, run: run.accession) + fastq_dir.glob("#{run.accession}{,_*}.fastq.bz2.partial")).each(&:delete)

    result.fastqs.each do |fastq|
      DRA::ReadsTree.move fastq, fastq_dir.join(fastq.basename)
    end

    # Last: it is what says the run is in the tree.
    DRA::ReadsTree.move result.sra, tree.sra(experiment:, run: run.accession)

    dir.rmtree
  end

  # What an analysis's directory has that the record no longer names — an
  # earlier attempt's, before an edit — would be published with it.
  def clear_analyses(row, analyses)
    tree = DRA::ReadsTree.at(:private)

    analyses.group_by { it.object['accession'] }.each do |analysis, entries|
      names = entries.map { self.class.analysis_file_name(it) }

      tree.analysis_dir(submission: row.accession, analysis:).glob('*').each do |path|
        path.delete unless names.include?(path.basename.to_s)
      end
    end
  end

  # An analysis's file is published as it was sent, as D-way published it,
  # beside the submission's fastq; under its own name, as D-way's took the
  # name the record gave it. One there whole already is not copied again.
  def place(row, entry, interrupt:)
    analysis = entry.object['accession'].to_s

    raise Failed, "#{row.accession}: #{entry.where} has no accession" unless analysis.match?(DRA::SubmissionFiles::OBJECT_FORMAT)

    path     = DRA::ReadsTree.at(:private).analysis_dir(submission: row.accession, analysis:).join(self.class.analysis_file_name(entry))

    return if path.file? && path.size == entry.blob.byte_size

    partial = path.sub_ext("#{path.extname}.partial").tap { it.dirname.mkpath }

    partial.open('wb') {|file|
      entry.blob.download do |chunk|
        file.write chunk
        interrupt.()
      end
    }

    partial.chmod DRA::ReadsTree::FILE_MODE
    partial.rename path
  end
end
