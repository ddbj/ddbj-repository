class SubmissionBelongsToRequest < ActiveRecord::Migration[7.1]
  def change
    add_reference :submissions, :request, foreign_key: true, index: true

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE submissions SET request_id = requests.id
          FROM requests
          WHERE submissions.id = requests.submission_id
        SQL
      end

      dir.down do
        execute <<~SQL
          UPDATE requests SET submission_id = submissions.id
          FROM submissions
          WHERE requests.id = submissions.request_id
        SQL
      end
    end

    change_column_null :submissions, :request_id, false
    remove_reference :requests, :submission, foreign_key: true, index: true
    remove_reference :submissions, :user, foreign_key: true, index: true
  end
end
