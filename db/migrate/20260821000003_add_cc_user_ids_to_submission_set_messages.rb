# Copying a colleague in on a set's conversation.
#
# The same field the per-request thread carries, for the same reason: it
# is what a curator does in mail without thinking about it, and without
# it the only way to bring somebody in is to tell them out of band —
# which stops the thread being the record of who was asked.
class AddCcUserIdsToSubmissionSetMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :submission_set_messages, :cc_user_ids, :jsonb, null: false, default: []
  end
end
