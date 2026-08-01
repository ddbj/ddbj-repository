# "Stop telling me about this one."
#
# A participation is a subscription, and it is created by acting: reply
# once to a thread somebody else owns and it follows you from then on.
# Usually that is what you want, which is why it is the default — but a
# curator dragged into a request they have no further part in had no way
# out, and a queue nobody can put things down in stops being read.
#
# Separate from the row itself because the row also records that they
# worked here, which unsubscribing does not undo.
class AddUnsubscribedAtToSubmissionRequestParticipants < ActiveRecord::Migration[8.1]
  def change
    add_column :submission_request_participants, :unsubscribed_at, :datetime
  end
end
