# Tells an account what is about to be let go of.
#
# A file waits in the unassigned files for a week (ExpireUnassignedFilesJob)
# and then goes, and for DRA that is reads measured in tens of GB: what has to
# be avoided is somebody finding out by looking. So two days before, one mail
# per account listing what is due, in the order it is due.
#
# One mail per account and not per file: an account uploads a run's files
# together, and a run is what its owner will act on.
class ExpiringUnassignedFilesNotifier
  # How long before the end. Two days is enough to answer it on a working day
  # after a weekend day, and short enough that the mail is about something the
  # reader still remembers uploading.
  NOTICE_DAYS = 2

  Result = Data.define(:notified_file_count, :notified_user_count, :skipped_user_count)

  def self.call(...) = new(...).call

  def initialize(notice_days: NOTICE_DAYS)
    @notice_days = notice_days
  end

  def call = notify(candidates.to_a)

  # Due within the notice window and not yet spoken for. A window rather than
  # a day, so a run that does not happen is caught by the next one; the notice
  # rows are what stops that catching up from repeating itself.
  def candidates
    User
      .unassigned_file_attachments
      .where(created_at: ExpireUnassignedFilesJob::KEEP_FOR.ago..(ExpireUnassignedFilesJob::KEEP_FOR - @notice_days.days).ago)
      .where.not(id: UnassignedFileNotice.select(:attachment_id))
      .includes(:blob, :record)
      .order(:created_at, :id)
  end

  def notify(attachments)
    # An account we have no address for is left unmarked, so it is told as soon
    # as an address arrives (a login, or SyncUserEmailsJob) rather than never.
    mailable, skipped = attachments.group_by(&:record).partition {|user, _| user.email.present? }

    sent_at = Time.current

    mailable.each do |user, files|
      UnassignedFileMailer.with(user:, attachments: files).expiry_notice.deliver_later

      UnassignedFileNotice.insert_all(files.map { {attachment_id: it.id, sent_at:} })
    end

    Result.new(
      notified_file_count: mailable.sum {|_user, files| files.size },
      notified_user_count: mailable.size,
      skipped_user_count:  skipped.size
    )
  end
end
