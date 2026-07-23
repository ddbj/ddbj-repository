# Daily driver for the DistributionNotifier. Kept thin — the candidate
# selection and mailing live in the service so they stay testable and can
# be triggered from an admin "run now" later (DB-2005).
class DistributionNotifierJob < ApplicationJob
  def perform
    DistributionNotifier.call
  end
end
