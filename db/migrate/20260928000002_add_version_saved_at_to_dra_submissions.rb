# How far into D-way's history the import has read: when the latest version
# it has taken in was saved there. The next run takes the versions saved
# after it.
#
# Kept apart from the chain: a version that changes nothing the record says
# writes no patch, and a mark read off the chain would stay behind it — the
# next run would take it again and, where a curator has edited the record
# since, write a patch putting the edit back.
class AddVersionSavedAtToDRASubmissions < ActiveRecord::Migration[8.1]
  def change
    add_column :dra_submissions, :version_saved_at, :datetime
  end
end
