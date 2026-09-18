# Tells an account what is about to be let go of.
#
# A file waits in the unassigned files for a week (ExpireUnassignedFilesJob)
# and then goes, and for DRA that is reads measured in tens of GB: what has to
# be avoided is somebody finding out by looking. So two days before, one mail
# per account listing what is due, in the order it is due.
#
# One mail per account and not per file: an account uploads a run's files
# together, and a run is what its owner will act on.
#
# Every file this leaves behind gets a row either way — mailed or not — because
# that row is what lets the file be deleted at all. An account nothing can be
# sent to still loses the file; what it must not do is lose it with no record
# that nobody was told.
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

  # Due within the notice window and not yet spoken for. A window rather than a
  # day, so a run that does not happen is caught by the next one; the notice
  # rows are what stops that catching up from repeating itself.
  #
  # Files a submission already holds are left out. They are not going anywhere
  # — the expiry only detaches, and the submission keeps the bytes — and
  # ReleaseAssignedFilesJob will take them out of the list tonight anyway.
  # Announcing one would have the owner upload 40 GB again for nothing.
  def candidates
    User
      .unassigned_file_attachments
      .where(created_at: ExpireUnassignedFilesJob::KEEP_FOR.ago..(ExpireUnassignedFilesJob::KEEP_FOR - @notice_days.days).ago)
      .where.not(blob_id: User.assigned_file_blob_ids)
      .where.not(id: UnassignedFileNotice.select(:attachment_id))
      .includes(:blob, :record)
      .order(:created_at, :id)
  end

  def notify(attachments)
    mailable, unreachable = attachments.group_by(&:record).partition {|user, _| reachable?(user) }

    sent_at = Time.current

    mailable.each do |user, files|
      UnassignedFileMailer.with(user:, attachment_ids: files.map(&:id)).expiry_notice.deliver_later

      record files, result: :delivered, sent_at:
    end

    # Recorded, not mailed. `skip_reason` is the difference between an address
    # we have never learned and one this deployment refuses to write to, which
    # are different problems for whoever reads these rows.
    unreachable.each do |user, files|
      record files, result: :skipped, sent_at:,
                    skip_reason: user.email.present? ? UnassignedFileNotice::NOT_DELIVERED : UnassignedFileNotice::NO_ADDRESS
    end

    Result.new(
      notified_file_count: mailable.sum {|_user, files| files.size },
      notified_user_count: mailable.size,
      skipped_user_count:  unreachable.size
    )
  end

  private

  # Having an address is not the same as being written to: outside production
  # — and in production, for everyone outside the allowed domains — the
  # interceptor drops the mail on its way out. Asking it here is what keeps a
  # row from claiming a delivery that never happened.
  def reachable?(user) = user.email.present? && MailDomainAllowlistInterceptor.delivers_to?(user.email)

  def record(files, result:, sent_at:, skip_reason: nil)
    UnassignedFileNotice.insert_all(
      files.map { {attachment_id: it.id, result:, skip_reason:, sent_at:} }
    )
  end
end
