module Admin
  # DistributionNotifier management (DB-2005): show who is due for a release
  # notice and send it manually (whole batch or one submitter). The daily
  # schedule stays in recurring.yml; this is the manual / audit surface.
  class DistributionNoticesController < ApplicationController
    def index
      @candidates_by_user = DistributionNotifier.new.candidates.to_a.group_by { it.submission.user }
    end

    # "Send now" — all pending, or just one submitter's when user_id is given.
    def create
      projects = DistributionNotifier.new.candidates.to_a
      projects = projects.select { it.submission.user_id == params[:user_id].to_i } if params[:user_id].present?

      result = DistributionNotifier.new.notify(projects)

      notice = "Sent #{result.notified_project_count} notice(s) to #{result.notified_user_count} submitter(s)."
      notice += " #{result.skipped_user_count} submitter(s) skipped: no address on file." if result.skipped_user_count.positive?

      redirect_to admin_distribution_notices_path, notice:
    end
  end
end
