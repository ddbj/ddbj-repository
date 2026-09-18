# What has already been said about a file's expiry — or could not be said, and
# why. Keyed to the attachment and gone with it: once the file has left the
# list there is nothing left to warn about.
#
# It is also the permission to delete: ExpireUnassignedFilesJob only lets go of
# a file that has a row here, so "announced before it went" holds by
# construction rather than by the two jobs happening to agree.
class CreateUnassignedFileNotices < ActiveRecord::Migration[8.1]
  def change
    create_table :unassigned_file_notices do |t|
      t.references :attachment, null: false, index: {unique: true},
                                foreign_key: {to_table: :active_storage_attachments, on_delete: :cascade}

      t.string   :result,      null: false
      t.string   :skip_reason
      t.datetime :sent_at,     null: false
    end
  end
end
