class AddErrorCodeToSubmissionRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :submission_requests, :error_code, :string
  end
end
