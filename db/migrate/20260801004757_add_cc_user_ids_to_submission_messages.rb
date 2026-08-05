# "Have a look at this one too."
#
# Curators run this conversation over email today, where copying a
# colleague in is one field and no ceremony. Without it the only way to
# bring somebody in is to tell them out of band — at which point the
# thread stops being the record of who was asked what.
#
# Stored on the message rather than only as a subscription, because being
# copied in is something that happened at a moment, in a thread, by
# somebody. The subscription it creates is a consequence.
class AddCcUserIdsToSubmissionMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :submission_messages, :cc_user_ids, :jsonb, default: [], null: false
  end
end
