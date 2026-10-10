# Daily driver for HoldDateRelease. Re-runnable from the start wherever it
# was stopped: what it releases is no longer selected by the next run.
class ReleaseOnHoldDateJob < ApplicationJob
  def perform
    HoldDateRelease.call
  end
end
