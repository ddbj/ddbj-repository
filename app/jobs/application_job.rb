class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # A keyword argument off a job instance, for the `discard_on` /
  # `retry_on` handlers that get the job rather than its arguments.
  # Tolerant of ActiveJob's symbol-key serialisation quirks and of an
  # adapter that round-trips kwargs as string-keyed hashes — and of a job
  # with no arguments at all, which is otherwise a NoMethodError raised
  # from inside an error handler.
  def self.job_kwarg(job, name)
    arg = job.arguments.first
    return nil unless arg.is_a?(Hash)

    arg[name] || arg[name.to_s]
  end
end
