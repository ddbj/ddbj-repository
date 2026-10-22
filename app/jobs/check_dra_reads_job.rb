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
# file up to DRA::SRAToolkit::TIMEOUT, so a reading has no bound short of
# days; and every way a job ends — finished, failed, killed, its process
# gone — releases the limit itself, so a long duration costs nothing.
#
# Taken up again where it was stopped (ActiveJob::Continuable): a deploy
# gives a job under a minute to stop, and a run's reading takes hours. Each
# run's findings are written as it is read and the cursor moved past it, so
# a stopped job reads again only the run it was in; the tool running then
# is stopped with it (DRA::ReadCheck's `interrupt`), and the files it had
# copied out are kept for the next attempt, in a directory of the check's
# own: a run's part of it once the run is read, the rest once the check is
# concluded.
#
# Taken up again ahead of the readings that have not started (a lower
# priority number; Solid Queue lets the waiting ones in by priority, then
# age), so a half-read check does not wait days behind the queue with its
# copies on disk. And not for ever: a run longer than the time between
# deploys would start again at every one — past MAX_RESUMPTIONS the job
# fails, and give_up_stopped_readings ends the check as not carried out.
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
  include ActiveJob::Continuable

  MAX_RESUMPTIONS = 20

  # The limit the checks share with the builds (BuildDRAReadsJob): its
  # group is the class's otherwise, and each class would have one of its own.
  DRA_READS = {to: 1, key: 'dra_reads', group: 'dra_reads', duration: 7.days}.freeze

  queue_with_priority 10

  self.max_resumptions = MAX_RESUMPTIONS
  self.resume_options  = {wait: 5.seconds, priority: 0}
  limits_concurrency(**DRA_READS)

  # The check it was for is gone (its request deleted).
  discard_on ActiveJob::DeserializationError

  def perform(validation)
    return unless validation.running?

    request = validation.subject
    record  = request.ddbj_record.open { Oj.load(it.read, mode: :strict) }
    files   = DRA::RecordFiles.new(record, request.user.unassigned_files.blobs)

    gone = files.unmatched.map {|entry|
      detail('TRD_R0022', :error, entry.object, "#{entry.where} #{entry.problem}.")
    }

    return conclude(validation, gone) if gone.any?

    runs = DRA::RecordRuns.new(record, files).to_a

    step :read do |step|
      runs.drop(step.cursor.to_i).each.with_index(step.cursor.to_i) do |run, position|
        found = read(run, dir: kept_dir(validation).join("run-#{run.index}"), interrupt: -> { step.checkpoint! })

        DDBJValidatorCheck.add_details validation, found
        kept_dir(validation).join("run-#{run.index}").rmtree

        step.set! position + 1
      end
    end

    conclude validation, []
  rescue DRA::SRAToolkit::ToolMissing, DRA::SRAToolkit::TimedOut => e
    give_up validation, "the reads could not be read here (#{e.message})"
  rescue StandardError => e
    # The store not answering, the disk full: not the reads' doing. Ended
    # as not carried out, for the submitter to run again, rather than left
    # checking until the sweep finds the job failed.
    Rails.error.report e, context: {validation_id: validation.id}

    give_up validation, "the reads could not be read (#{e.class})"
  end

  KEPT_PREFIX = 'dra-reads-'

  SAID_LINE_LIMIT = 500

  # Where a check's copies are kept between attempts.
  def self.kept_dir(validation_id) = Pathname.new(Rails.application.config_for(:app).work_dir!).join("#{KEPT_PREFIX}#{validation_id}")

  # The copies kept for checks that will not be taken up again: ended, or
  # gone. Run after give_up_stopped_readings, which ends the dead ones.
  def self.discard_abandoned_copies
    kept_dir('*').dirname.glob("#{KEPT_PREFIX}*").each do |dir|
      dir.rmtree unless Validation.running.exists?(id: dir.basename.to_s.delete_prefix(KEPT_PREFIX))
    end
  end

  private

  # Ended, however: the copies kept for another attempt go.
  def conclude(validation, details)
    DDBJValidatorCheck.conclude validation, details
  ensure
    discard_copies validation
  end

  def give_up(validation, reason)
    DDBJValidatorCheck.give_up validation, reason
  ensure
    discard_copies validation
  end

  def discard_copies(validation) = kept_dir(validation).rmtree

  def kept_dir(validation) = self.class.kept_dir(validation.id)

  def read(run, dir:, interrupt:)
    object    = run.object
    filetypes = run.filetypes

    return [detail('TRD_R0023', :error, object, "#{run.where} names no files; a run is its reads.")] if run.entries.empty?
    return [detail('TRD_R0023', :error, object, "#{run.where} has a file that states no filetype.")] if filetypes.include?('')
    return [detail('TRD_R0023', :error, object, "#{run.where} has files of more than one filetype (#{filetypes.join(', ')}); a run's reads are read together.")] if filetypes.size > 1
    return [detail('TRD_R0024', :warning, object, "#{run.where}: #{filetypes.first} files are not read here yet; its reads were not checked.")] unless DRA::ReadCheck::FILETYPES.key?(filetypes.first)

    result = DRA::ReadCheck.call(files: run.entries.map(&:blob), filetype: filetypes.first, platform: run.platform, dir:, interrupt:)

    if !result.ok?
      [detail('TRD_R0023', :error, object, "#{run.where}: the reads could not be read. #{said(result, dir)}")]
    elsif result.errors.any?
      [detail('TRD_R0024', :warning, object, "#{run.where}: the reads were read, but some records could not be and were left out. #{said(result, dir)}")]
    else
      []
    end
  end

  # What the tools said, the last of it: enough to know what is wrong. It
  # is mailed and kept in the request's thread, so it names the files as
  # the submitter does rather than where they were copied to here, and a
  # line that runs on is cut short.
  def said(result, dir)
    lines  = result.errors.last(5).presence || result.output.lines.last(5)
    copies = %r{#{Regexp.escape(dir.to_s)}/(?:in/\d+/)?}

    lines.map { it.strip.gsub(copies, '').truncate(SAID_LINE_LIMIT) }.join("\n").strip
  end

  def detail(code, severity, object, message) = {code:, severity:, entry_id: object['alias'].presence, message:}
end
