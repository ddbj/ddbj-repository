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

  def assigned = User.unassigned_file_attachments.where(blob_id: User.assigned_file_blob_ids)
end
