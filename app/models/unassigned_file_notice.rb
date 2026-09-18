# What was said to a file's owner about its expiry, or why nothing was.
#
# One row per file, gone with the attachment it is about (the foreign key
# cascades). ExpireUnassignedFilesJob reads it as the permission to delete: a
# file with no row here is one nobody has been told about, and it waits.
#
# A row saying `skipped` is that permission too. An account whose address we do
# not have cannot be told however long the file waits — so the row records that
# the file went unannounced, rather than leaving the file to accumulate for ever
# with nobody the wiser.
#
# Mail restricted to a few domains (`mail_allowed_domains`) is not one of these
# cases: that is how dev and staging are run, and the accounts there know it.
class UnassignedFileNotice < ApplicationRecord
  NO_ADDRESS = 'no_address'.freeze

  belongs_to :attachment, class_name: 'ActiveStorage::Attachment'

  enum :result, {delivered: 'delivered', skipped: 'skipped'}, validate: true
end
