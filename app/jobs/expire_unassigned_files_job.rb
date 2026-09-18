# Lets go of a file nothing was ever assigned.
#
# The list is where a file waits to be used, and waiting has to end somewhere:
# an account that uploads a run's reads and never comes back would otherwise
# hold those bytes for ever. A week, counted from when the file appeared in the
# list — so an importer that ever fills this list from somewhere else (D-way's
# upload directory is the one in view) must not carry the original times over,
# or everything it writes is a week old on arrival.
#
# Detaching is all this does. What happens to the bytes is the same question as
# for any blob nothing holds, and PurgeUnattachedUploadsJob answers it half an
# hour later — for a file this old, by removing them.
class ExpireUnassignedFilesJob < ApplicationJob
  KEEP_FOR = 7.days

  def perform
    User.unassigned_file_attachments.where(created_at: ..KEEP_FOR.ago).find_each do |attachment|
      attachment.destroy!
    rescue StandardError => e
      # One row that cannot be let go of is not a reason to stop: `find_each`
      # walks ids upward, so everything after it would wait another day, and
      # the day after that.
      Rails.error.report e, context: {attachment_id: attachment.id}, source: self.class.name
    end
  end
end
