# Jobs whose process went away under them run again from the start.
#
# A deploy already does this: it gives a worker
# config.solid_queue.shutdown_timeout to finish, then stops it and puts
# back whatever it was running, and the new worker runs that from the
# start. So every job here has to be one that can be run again from the
# start, wherever it was stopped — carrying on from what it committed, or
# finding it has nothing left to do (CLAUDE.md, "Jobs stopped part way").
#
# What a deploy does not put back is a job whose whole process went — the
# container killed before the worker could stop, the host down. Solid Queue
# records those failed, when it finds the process gone, and never runs
# them; their requests would stay applying and their uploads verifying.
# This runs them as a deploy would have.
#
# "Gone" is Solid Queue's guess from a heartbeat that stopped, and a worker
# that lost the queue database for a while can still be running the job.
# The jobs that would do harm run twice at once take a lock on what they
# work on (AdvisoryLock), so the second finds the first and stands down.
#
# Not a worker that died while its supervisor lived (ProcessExitError):
# that is likeliest the job itself — memory it ran out of — and run again,
# it would die again, every few minutes. It stays among the failed jobs
# for a person (/admin/jobs). Nor one that failed longer ago than RECENT:
# a person has had it in front of them since, and a mail or an apply run
# months late is not the deploy's work being finished.
class RecoverKilledJobsJob < ApplicationJob
  GONE = %w[
    SolidQueue::Processes::ProcessPrunedError
    SolidQueue::Processes::ProcessMissingError
  ].freeze

  RECENT = 1.day

  def perform
    gone = SolidQueue::FailedExecution.where(created_at: RECENT.ago..).where("error::jsonb ->> 'exception_class' IN (?)", GONE)

    gone.find_each do |failed|
      Rails.logger.info "Running again job #{failed.job_id}, whose process went away under it"

      failed.retry
    end
  end
end
