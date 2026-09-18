# Lets go of a file nothing was ever assigned.
#
# The list is where a file waits to be used, and waiting has to end somewhere:
# an account that uploads a run's reads and never comes back would otherwise
# hold those bytes for ever. Seven days, which is also how long the store will
# carry an unfinished upload on (MultipartUpload::RESUMABLE_FOR) — one number
# for how long a file that is going nowhere is kept.
#
# Detaching is all this does. What happens to the bytes is the same question as
# for any blob nothing holds, and PurgeUnattachedUploadsJob answers it half an
# hour later — for a file this old, by removing them.
class ExpireUnassignedFilesJob < ApplicationJob
  KEEP_FOR = 7.days

  def perform
    ActiveStorage::Attachment
      .where(record_type: 'User', name: User::UNASSIGNED_FILES_ATTACHMENT, created_at: ..KEEP_FOR.ago)
      .find_each(&:destroy!)
  end
end
