# Delete job rows that have already finished.
#
# SolidQueue keeps one row per job for ever unless something removes it:
# `clear_finished_jobs_after` names a retention window but nothing acts
# on it, so the table only grows. Staging had 1,086,334 finished rows by
# the time anyone looked, most of them from bulk imports that write one
# job per submission — production will do the same.
#
# A finished job answers no question a day later. The queue browser
# shows what is running and what failed, and failures are kept: this
# only removes rows that ran to completion.
class ClearFinishedJobsJob < ApplicationJob
  def perform
    # `SolidQueue.clear_finished_jobs_after` (1 day) is the window; the
    # defaults batch the delete so a first run over a million rows does
    # not hold one long transaction.
    SolidQueue::Job.clear_finished_in_batches
  end
end
