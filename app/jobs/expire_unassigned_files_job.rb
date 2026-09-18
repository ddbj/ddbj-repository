# Lets go of a file nothing was ever assigned.
#
# The list is where a file waits to be used, and waiting has to end somewhere:
# an account that uploads a run's reads and never comes back would otherwise
# hold those bytes for ever. A week, counted from when the file appeared in the
# list — so an importer that ever fills this list from somewhere else (D-way's
# upload directory is the one in view) must not carry the original times over,
# or everything it writes is a week old on arrival.
#
# **Only what has been announced.** ExpiringUnassignedFilesNotifier leaves a
# row for every file it passes — mailed, or recorded as unmailable — and this
# takes that row as the permission to delete. Without it the two jobs would
# each be right on their own while a file slipped between them: a notice run
# that did not happen, a mail nothing could be sent to, a window that missed by
# a day. The file then waits, which is the safe way round.
#
# Detaching is all this does. What happens to the bytes is the same question as
# for any blob nothing holds, and PurgeUnattachedUploadsJob answers it half an
# hour later — for a file this old, by removing them.
class ExpireUnassignedFilesJob < ApplicationJob
  KEEP_FOR = 7.days

  # The notice has to have gone out before the day it is acted on, so that a
  # file is never announced and deleted in the same night.
  ANNOUNCED_BY = 1.day

  def perform
    announced.find_each do |attachment|
      attachment.destroy!
    rescue StandardError => e
      # One row that cannot be let go of is not a reason to stop: `find_each`
      # walks ids upward, so everything after it would wait another day, and
      # the day after that.
      Rails.error.report e, context: {attachment_id: attachment.id}, source: self.class.name
    end
  end

  private

  def announced
    User
      .unassigned_file_attachments
      .where(created_at: ..KEEP_FOR.ago)
      .where(id: UnassignedFileNotice.where(sent_at: ..ANNOUNCED_BY.ago).select(:attachment_id))
  end
end
