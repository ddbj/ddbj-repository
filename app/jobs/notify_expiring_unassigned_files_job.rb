# Daily driver for ExpiringUnassignedFilesNotifier. Thin, like
# DistributionNotifierJob: what to say and to whom lives in the service.
class NotifyExpiringUnassignedFilesJob < ApplicationJob
  def perform
    result = ExpiringUnassignedFilesNotifier.call

    # The skipped count is the one worth seeing: those files will go without
    # anybody having been told, and the rows say why.
    Rails.logger.info "[expiring files] told #{result.notified_user_count} " \
                      "account(s) about #{result.notified_file_count} file(s); " \
                      "#{result.skipped_user_count} could not be told"
  end
end
