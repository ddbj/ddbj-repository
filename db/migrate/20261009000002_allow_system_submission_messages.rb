class AllowSystemSubmissionMessages < ActiveRecord::Migration[8.1]
  # A notice DDBJ posts of its own accord — accessions issued, data made
  # public — has no person behind it. Nothing else goes without one.
  def change
    change_column_null :submission_messages, :user_id, true

    add_check_constraint :submission_messages, "user_id IS NOT NULL OR author_role = 'system'", name: 'submission_messages_author'
  end
end
