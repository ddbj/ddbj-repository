class RepointSubmissionMessagesToRequest < ActiveRecord::Migration[8.1]
  # The submitter ↔ curator thread now hangs off the SubmissionRequest
  # instead of the Submission, so the conversation can start before
  # Apply — when only a request exists and no Submission has been
  # materialised yet. Messaging is not yet in operation, so existing
  # rows are dropped rather than remapped submission → request.
  def up
    execute 'DELETE FROM submission_messages'

    # DROP COLUMN cascades to the FK and every index that includes
    # submission_id (the single-column index plus the two composites).
    remove_column :submission_messages, :submission_id

    add_reference :submission_messages, :submission_request, null: false, foreign_key: true
    add_index :submission_messages, %i[submission_request_id author_role read_at]
    add_index :submission_messages, %i[submission_request_id created_at]
  end

  def down
    execute 'DELETE FROM submission_messages'

    remove_column :submission_messages, :submission_request_id

    add_reference :submission_messages, :submission, null: false, foreign_key: true
    add_index :submission_messages, %i[submission_id author_role read_at]
    add_index :submission_messages, %i[submission_id created_at]
  end
end
