# A DRA record's runs, each with the files it names (DRA::RecordFiles) and
# the experiments it is part of: those relations from the run name, found
# the way DRA::Converter writes references (DDBJRecord::References).
class DRA::RecordRuns
  include Enumerable

  Run = Data.define(:object, :index, :entries, :experiments) do
    def where     = "runs[#{index}]"
    def accession = object['accession']

    # The one its reads are filed under (DRA::ReadsTree).
    def experiment = experiments.first

    # As latf-load is told it: the run's own, or else the first its
    # experiments state.
    def platform = platform_of(object) || experiments.lazy.filter_map { platform_of(it) }.first

    # As the record states them, compared without case: D-way read a run
    # only when its files were all of one.
    def filetypes = entries.map { it.file['filetype'].to_s.strip.downcase }.uniq

    private

    def platform_of(object) = (object['platform'] if object.is_a?(Hash)).then { it['type'] if it.is_a?(Hash) }
  end

  def initialize(record, files)
    @record     = record
    @files      = files
    @references = DDBJRecord::References::Index.new(record)
  end

  # Every run, with its files — none, for a run that names none.
  def each(&)
    by_index = @files.entries.select { it.list == 'runs' }.group_by(&:index)

    Array(@record['runs']).each_with_index.filter_map {|object, index|
      Run.new(object:, index:, entries: by_index.fetch(index, []), experiments: experiments(object)) if object.is_a?(Hash)
    }.each(&)
  end

  private

  # Resolved once: a document of a thousand runs each naming its
  # experiment would otherwise read every relation for every run.
  def experiments(run)
    @experiments ||= Array(@record['relations']).each_with_object({}.compare_by_identity) {|relation, by_run|
      next unless relation.is_a?(Hash) && relation['source'].is_a?(Hash) && relation['target'].is_a?(Hash)
      next unless relation['source']['type'] == 'run' && relation['target']['db'] == 'experiment'

      source = @references.source('runs', relation['source'])
      target = @references.target('experiments', relation['target'])

      (by_run[source] ||= []) << target if source && target
    }

    @experiments.fetch(run, []).uniq(&:object_id)
  end
end
