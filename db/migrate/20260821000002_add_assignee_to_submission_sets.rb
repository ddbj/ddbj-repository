# Who is answering a set's conversation.
#
# The set axis had no claim, so a waiting set sat in every curator's queue
# until somebody answered it — which is the "visible to everyone, owned by
# nobody" that the three-way split of the queue exists to fix. Following
# does not fill the gap: it is written by replying, so it records what
# already happened rather than saying "I am taking this".
#
# Deliberately only about the conversation. A set has no state to move
# through, and this column must not become the seed of one.
class AddAssigneeToSubmissionSets < ActiveRecord::Migration[8.1]
  def change
    add_reference :submission_sets, :assignee, foreign_key: {to_table: :users}
  end
end
