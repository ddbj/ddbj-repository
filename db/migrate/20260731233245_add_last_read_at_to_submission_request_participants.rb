# Who has seen what, per curator.
#
# The thread was marked read for EVERY curator the moment any one of them
# opened the tab, so a colleague glancing at it took the request out of
# the whole team\'s queue — including the queue of whoever was assigned to
# it, and of whoever had replied there before. "Somebody looked" and "I
# know about this" are not the same fact, and only the first was recorded.
#
# The row already exists per (request, curator); this is where that
# curator got to. A participation is now a subscription in the GitHub
# sense, and assignment creates one — an assignee who has not touched
# anything yet had no row at all, so there was nowhere to record that
# they had seen it.
class AddLastReadAtToSubmissionRequestParticipants < ActiveRecord::Migration[8.1]
  # No backfill: NULL means "has put nothing aside", and the baseline for
  # everyone is the thread's own state — an unanswered submitter message.
  # Existing settled conversations are answered, so they start settled.
  def change
    add_column :submission_request_participants, :last_read_at, :datetime
  end
end
