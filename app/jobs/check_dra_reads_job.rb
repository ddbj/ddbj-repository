# The second half of checking a DRA record: once ddbj-validator has found
# nothing wrong with its metadata, each run's reads are read as the archive
# will read them (DRA::ReadCheck), and what that finds is added to the
# validator's. Only then is the check concluded — ready to apply, or not.
#
# One at a time: a run of hundreds of gigabytes takes hours and the host's
# memory with it, so two at once would take twice that. One waiting for its
# turn holds no worker thread (Solid Queue blocks it before claiming), so
# other jobs do not wait behind it. The limit outlasts the longest a check
# may take (DRA::ReadCheck::TIMEOUT), so it is never lifted while one runs.
#
#   TRD_R0022  a file the record names is no longer among the uploads (taken
#              out, or let go of, since the record was taken in)
#   TRD_R0023  a run's reads could not be read, or mix filetypes that are
#              read apart
#   TRD_R0024  a warning: a run's reads were read with records dropped as
#              unreadable, or are of a filetype not read here yet
#
# Analyses' files (alignments, assemblies, tables) are not reads, and are
# not read here.
class CheckDRAReadsJob < ApplicationJob
  limits_concurrency to: 1, key: 'dra_reads', duration: DRA::ReadCheck::TIMEOUT + 1.hour

  def perform(validation)
    return unless validation.running?

    request = validation.subject
    record  = request.ddbj_record.open { Oj.load(it.read, mode: :strict) }
    files   = DRA::RecordFiles.new(record, request.user)

    details = files.unmatched.map {|entry|
      detail('TRD_R0022', :error, entry, "#{entry.where} #{entry.problem}.")
    }

    details = runs(files).flat_map { read(record, *it) } if details.empty?

    DDBJValidatorCheck.conclude validation, details
  rescue DRA::ReadCheck::ToolMissing, DRA::ReadCheck::TimedOut => e
    DDBJValidatorCheck.give_up validation, "the reads could not be read here (#{e.message})"
  end

  private

  def runs(files)
    files.entries.select { it.list == 'runs' }.group_by(&:index).values.map { [it.first.object, it.first.index, it] }
  end

  def read(record, run, index, entries)
    filetypes = entries.map { it.file['filetype'].to_s }.uniq
    entry     = entries.first

    return [detail('TRD_R0023', :error, entry, "runs[#{index}] has files of more than one filetype (#{filetypes.join(', ')}); a run's reads are read together.")] if filetypes.size > 1
    return [detail('TRD_R0024', :warning, entry, "runs[#{index}]: #{filetypes.first} files are not read here yet; its reads were not checked.")] unless DRA::ReadCheck::FILETYPES.key?(filetypes.first)

    result = DRA::ReadCheck.call(files: entries.map(&:blob), filetype: filetypes.first, platform: platform(record, run, index))

    if !result.ok?
      [detail('TRD_R0023', :error, entry, "runs[#{index}]: the reads could not be read. #{said(result)}")]
    elsif result.errors.any?
      [detail('TRD_R0024', :warning, entry, "runs[#{index}]: the reads were read, but some records could not be and were left out. #{said(result)}")]
    else
      []
    end
  end

  # The platform of the experiment the run belongs to (relations, part_of
  # an experiment), as latf-load is told it.
  def platform(record, run, index)
    relation = Array(record['relations']).find {|r|
      next false unless r.is_a?(Hash) && r['source'].is_a?(Hash) && r['target'].is_a?(Hash)

      source = r['source']

      source['type'] == 'run' && r['target']['db'] == 'experiment' &&
        (source['alias'].present? ? source['alias'] == run['alias'] : source['index'] == index)
    } or return nil

    target     = relation['target']
    experiment = Array(record['experiments']).find {|e|
      e.is_a?(Hash) && ((target['accession'].present? && e['accession'] == target['accession']) || (target['id'].present? && e['alias'] == target['id']))
    }

    experiment&.dig('platform', 'type')
  end

  # What the tools said, the last of it: enough to know what is wrong.
  def said(result) = result.errors.last(5).join("\n").presence || result.output.lines.last(5).join.strip

  def detail(code, severity, entry, message) = {code:, severity:, entry_id: entry.object['alias'].presence, message:}
end
