# That a file's expiry has been announced to its owner. One row per file, gone
# with the attachment it is about (the foreign key cascades), because once the
# file has left the list the notice has nothing left to be about.
class UnassignedFileNotice < ApplicationRecord
  belongs_to :attachment, class_name: 'ActiveStorage::Attachment'
end
