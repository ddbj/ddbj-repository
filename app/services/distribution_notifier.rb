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

  Result = Data.define(:notified_project_count, :notified_user_count, :skipped_user_count)

  def self.call(...) = new(...).call

  # How the daily run is configured, read from the same file SolidQueue
  # reads — so the screen cannot claim a schedule that was changed out
  # from under it. Nil where the environment has no recurring entry at
  # all, which is the truth in local development.
  def self.schedule
    Rails.application.config_for(:recurring)&.dig(:distribution_notifier, :schedule)
  rescue StandardError
    nil
  end

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
  #
  # `trigger` / `actor` are what the audit log records: the daily job is
  # nobody's decision, a manual send is somebody's.
  #
  # Every submitter gets a log row, mailed or not. One `sent_at` for the
  # whole call, so "the last run" is a group of rows sharing a timestamp
  # rather than a fuzzy window.
  def notify(projects, trigger: :scheduled, actor: nil)
    # Submitters we have no address for are left untouched — NOT marked as
    # notified — so they stay on the admin list instead of silently
    # vanishing, and the next run picks them up once the address arrives
    # (login, or SyncUserEmailsJob).
    mailable, skipped = projects.group_by { it.submission.user }.partition {|user, _| user.email.present? }

    sent_at = Time.current

    mailable.each do |user, user_projects|
      DistributionNotifierMailer.with(user:, projects: user_projects).release_notice.deliver_later

      Project.where(id: user_projects.map(&:id)).update_all(distribution_notified_at: sent_at)

      record(user, user_projects, sent_at:, trigger:, actor:, result: :delivered)
    end

    # One skip row per block, not one per attempt. A blocked submitter is
    # a candidate every day until their hold date passes, so recording
    # each run would bury the history under repeats of the same fact —
    # and "blocked since" would still read from the first of them anyway.
    already = DistributionNotice.currently_blocked_user_ids(skipped.map {|user, _| user.id })

    skipped.each do |user, user_projects|
      next if already.include?(user.id)

      record(user, user_projects, sent_at:, trigger:, actor:,
             result: :skipped, skip_reason: DistributionNotice::NO_ADDRESS)
    end

    Result.new(
      notified_project_count: mailable.sum {|_user, user_projects| user_projects.size },
      notified_user_count:    mailable.size,
      skipped_user_count:     skipped.size
    )
  end

  private

  def record(user, projects, sent_at:, trigger:, actor:, result:, skip_reason: nil)
    DistributionNotice.create!(
      user:, sent_at:, trigger:, actor:, result:, skip_reason:,
      accessions: projects.map(&:accession)
    )
  end
end
