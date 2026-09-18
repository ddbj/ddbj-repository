# Daily driver for ExpiringUnassignedFilesNotifier. Thin, like
# DistributionNotifierJob: what to say and to whom lives in the service.
class NotifyExpiringUnassignedFilesJob < ApplicationJob
  def perform
    ExpiringUnassignedFilesNotifier.call
  end
end
