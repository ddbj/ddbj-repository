# Takes out of an uploader's unassigned files what has since been assigned.
#
# That list is where a file waits between being uploaded and being assigned to
# a submission — for DRA, reads uploaded days before their metadata. Once a
# submission (or anything else) holds the same blob, the copy there waits for
# nothing, and leaving it would make the list everything the account ever sent
# rather than what is still to be assigned.
#
# Only the attachment goes. The bytes belong to whatever was assigned them,
# which is the reason the list attaches with `dependent: false`.
class ReleaseAssignedFilesJob < ApplicationJob
  def perform
    assigned.find_each(&:destroy!)
  end

  private

  # By record and name together: a message's attachments are called `files`
  # too, and attaching a file to a message assigns it as much as a submission
  # does.
  def assigned
    elsewhere = ActiveStorage::Attachment.where.not(record_type: 'User', name: User::UNASSIGNED_FILES_ATTACHMENT)

    ActiveStorage::Attachment
      .where(record_type: 'User', name: User::UNASSIGNED_FILES_ATTACHMENT)
      .where(blob_id: elsewhere.select(:blob_id))
  end
end
