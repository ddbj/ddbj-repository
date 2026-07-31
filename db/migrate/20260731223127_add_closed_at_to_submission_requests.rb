# "I am not taking this one further."
#
# A failed validation is a dead end: nothing advances it, and a corrected
# file arrives as a new request with no link back to this one. So every
# abandoned attempt sat in the submitter's list asking to be dealt with,
# for ever, and the ordering added with the task-axis list floats exactly
# those to the top — the abandoned attempts crowding out the live one.
#
# Kept apart from `status` on purpose. `validation_failed` is what
# happened; closing is what the submitter decided about it, and folding
# the second into the first would lose the first.
class AddClosedAtToSubmissionRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :submission_requests, :closed_at, :datetime
  end
end
