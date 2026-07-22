class AddModifiedDateToProjectsAndSamples < ActiveRecord::Migration[8.1]
  # D-way's project.modified_date / sample.modified_date — the row's
  # last-modified date, bumped on any change including a status flip to
  # suppressed. It is the `Updated` column of the BP/BS livelist, so we
  # carry it over (like release_date / dist_date) rather than deriving it.
  def change
    add_column :projects, :modified_date, :date
    add_column :samples,  :modified_date, :date
  end
end
