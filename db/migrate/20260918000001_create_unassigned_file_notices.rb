# What has already been said about a file's expiry, so a run that is repeated
# — or one that catches a file the previous day's run missed — does not say it
# twice. Keyed to the attachment, and gone with it: once the file leaves the
# list there is nothing left to warn about.
class CreateUnassignedFileNotices < ActiveRecord::Migration[8.1]
  def change
    create_table :unassigned_file_notices do |t|
      t.references :attachment, null: false, index: {unique: true},
                                foreign_key: {to_table: :active_storage_attachments, on_delete: :cascade}

      t.datetime :sent_at, null: false
    end
  end
end
