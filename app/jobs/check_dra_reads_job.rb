# The second half of checking a DRA record: once ddbj-validator has found
# nothing wrong with its metadata, each run's reads are read as the archive
# will read them (DRA::ReadCheck), and what that finds is added to the
# validator's. Only then is the check concluded — ready to apply, or not.
#
# One at a time: a run of hundreds of gigabytes takes hours and the host's
# memory with it, so two at once would take twice that. One waiting for its
# turn holds no worker thread (Solid Queue blocks it before claiming), so
# other jobs do not wait behind it.
#
# The limit's `duration` is how long Solid Queue holds it before deciding
# its holder is lost and letting the next one in — then two run, and the
# count drifts from there. A record's runs are read one after another, each
# file up to DRA::ReadCheck::TIMEOUT, so a reading has no bound short of
# days; and every way a job ends — finished, failed, killed, its process
# gone — releases the limit itself, so a long duration costs nothing.
#
# A deploy stops the worker gracefully: the job is put back and starts its
# reading again from the start, which for a large run is hours lost each
# deploy.
#
#   TRD_R0022  a file the record names is no longer among the uploads (taken
#              out, or let go of, since the record was taken in)
#   TRD_R0023  a run's reads could not be read, mix filetypes that are read
#              apart, or there are none: a run with no files, or files that
#              state no filetype
#   TRD_R0024  a warning: a run's reads were read with records dropped as
#              unreadable, or are of a filetype not read here yet
#
# Analyses' files (alignments, assemblies, tables) are not reads, and are
# not read here.
class CheckDRAReadsJob < ApplicationJob
  limits_concurrency to: 1, key: 'dra_reads', duration: 7.days

  # The check it was for is gone (its request deleted).
  discard_on ActiveJob::DeserializationError

  def perform(validation)
    return unless validation.running?

    request = validation.subject
    record  = request.ddbj_record.open { Oj.load(it.read, mode: :strict) }
    files   = DRA::RecordFiles.new(record, request.user)

    details = files.unmatched.map {|entry|
      detail('TRD_R0022', :error, entry.object, "#{entry.where} #{entry.problem}.")
    }

    details = runs(record, files).flat_map { read(record, *it) } if details.empty?

    DDBJValidatorCheck.conclude validation, details
  rescue DRA::ReadCheck::ToolMissing, DRA::ReadCheck::TimedOut => e
    DDBJValidatorCheck.give_up validation, "the reads could not be read here (#{e.message})"
  rescue StandardError => e
    # The store not answering, the disk full: not the reads' doing. Ended
    # as not carried out, for the submitter to run again, rather than left
    # checking until the sweep finds the job failed.
    Rails.error.report e, context: {validation_id: validation.id}

    DDBJValidatorCheck.give_up validation, "the reads could not be read (#{e.class})"
  end

  private

  # Every run, with its files — none, for a run that names none.
  def runs(record, files)
    by_index = files.entries.select { it.list == 'runs' }.group_by(&:index)

    Array(record['runs']).each_with_index.filter_map {|run, index|
      [run, index, by_index.fetch(index, [])] if run.is_a?(Hash)
    }
  end

  def read(record, run, index, entries)
    return [detail('TRD_R0023', :error, run, "runs[#{index}] names no files; a run is its reads.")] if entries.empty?

    filetypes = entries.map { it.file['filetype'].to_s.strip.downcase }.uniq

    return [detail('TRD_R0023', :error, run, "runs[#{index}] has a file that states no filetype.")] if filetypes.include?('')
    return [detail('TRD_R0023', :error, run, "runs[#{index}] has files of more than one filetype (#{filetypes.join(', ')}); a run's reads are read together.")] if filetypes.size > 1
    return [detail('TRD_R0024', :warning, run, "runs[#{index}]: #{filetypes.first} files are not read here yet; its reads were not checked.")] unless DRA::ReadCheck::FILETYPES.key?(filetypes.first)

    result = DRA::ReadCheck.call(files: entries.map(&:blob), filetype: filetypes.first, platform: platform(record, run))

    if !result.ok?
      [detail('TRD_R0023', :error, run, "runs[#{index}]: the reads could not be read. #{said(result)}")]
    elsif result.errors.any?
      [detail('TRD_R0024', :warning, run, "runs[#{index}]: the reads were read, but some records could not be and were left out. #{said(result)}")]
    else
      []
    end
  end

  # The run's own platform, or else that of the experiment it is part of
  # (a relation from the run to an experiment), as latf-load is told it.
  def platform(record, run)
    platform_type(run) || Array(record['relations']).lazy.filter_map {|relation|
      next unless relation.is_a?(Hash) && relation['source'].is_a?(Hash) && relation['target'].is_a?(Hash)
      next unless relation['source']['type'] == 'run' && relation['target']['db'] == 'experiment'
      next unless DDBJRecord::References.source(record, 'runs', relation['source']).equal?(run)

      platform_type(DDBJRecord::References.target(record, 'experiments', relation['target']))
    }.first
  end

  def platform_type(object) = (object['platform'] if object.is_a?(Hash)).then { it['type'] if it.is_a?(Hash) }

  # What the tools said, the last of it: enough to know what is wrong.
  def said(result) = result.errors.last(5).join("\n").presence || result.output.lines.last(5).join.strip

  def detail(code, severity, object, message) = {code:, severity:, entry_id: object['alias'].presence, message:}
end
