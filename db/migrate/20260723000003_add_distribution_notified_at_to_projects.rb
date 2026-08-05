class AddDistributionNotifiedAtToProjects < ActiveRecord::Migration[8.1]
  # When the DistributionNotifier has sent the release-notice for a project,
  # so the daily job doesn't re-notify the same record. NULL = not yet
  # notified.
  def change
    add_column :projects, :distribution_notified_at, :datetime
  end
end
