class AddDiffToSubmissionUpdates < ActiveRecord::Migration[8.1]
  def change
    add_column :submission_updates, :diff, :string
  end
end
