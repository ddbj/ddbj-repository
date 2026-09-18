# Takes out of the uploaders' files area what has since been named somewhere.
#
# The area is where a file waits between being uploaded and being used — for
# DRA, reads uploaded days before their metadata. Once a submission (or
# anything else) holds the same blob, the copy in the area is no longer waiting
# for anything, and leaving it there would make the area a list of everything
# the account ever sent rather than of what is still to be used.
#
# Only the attachment goes. The bytes belong to whatever named them, which is
# the reason the area attaches with `dependent: false`.
class ReleaseNamedFilesJob < ApplicationJob
  def perform
    # By record and name together: a message's attachments are called `files`
    # as well, and naming a file in a message is naming it.
    named = ActiveStorage::Attachment.where.not(record_type: 'User', name: User::FILES_ATTACHMENT)

    area.where(blob_id: named.select(:blob_id)).find_each(&:destroy!)
  end

  private

  def area = ActiveStorage::Attachment.where(record_type: 'User', name: User::FILES_ATTACHMENT)
end
