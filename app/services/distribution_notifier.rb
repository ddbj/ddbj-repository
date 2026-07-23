# frozen_string_literal: true

# Core of the DistributionNotifier (see DB-2005): finds embargoed records
# whose hold_date is coming up and mails the submitter a release notice,
# once per record. The daily job wraps this; the admin management surface
# (schedule / per-DB customisation / manual runs / audit) layers on top
# later.
#
# BP-only for now — hold_date lives on Project, and D-way BS never actually
# used a hold_date (its fields are commented out; BS release is date-driven).
class DistributionNotifier
  # Notify when hold_date is within this many days. TSUNAMI fires at
  # exactly 10 days out; a window (not an exact day) means a skipped run
  # still catches the record on the next one.
  NOTICE_DAYS = 10

  Result = Data.define(:notified_project_count, :notified_user_count)

  def self.call(...) = new(...).call

  def initialize(notice_days: NOTICE_DAYS)
    @notice_days = notice_days
  end

  def call
    notify(candidates.to_a)
  end

  # Embargoed (private), hold_date from today through the notice window, not
  # yet notified. Ordered so a submitter's mail lists earliest releases
  # first. Public so the admin list view can show who is due.
  def candidates
    Project
      .status_private
      .where(distribution_notified_at: nil, hold_date: Date.current..(Date.current + @notice_days.days))
      .includes(submission: %i[user request])
      .order(:hold_date, :id)
  end

  # Mail + mark a specific set of projects, one mail per submitter. Shared
  # by the daily run and the admin "send now" (whole batch or one submitter).
  def notify(projects)
    by_user = projects.group_by { it.submission.user }

    by_user.each do |user, user_projects|
      DistributionNotifierMailer.with(user:, projects: user_projects).release_notice.deliver_later

      Project.where(id: user_projects.map(&:id)).update_all(distribution_notified_at: Time.current)
    end

    Result.new(notified_project_count: projects.size, notified_user_count: by_user.size)
  end
end
