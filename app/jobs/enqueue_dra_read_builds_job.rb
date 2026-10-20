# See BuildDRAReadsJob.enqueue_due.
class EnqueueDRAReadBuildsJob < ApplicationJob
  def perform = BuildDRAReadsJob.enqueue_due
end
