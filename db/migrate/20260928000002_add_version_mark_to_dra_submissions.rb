# How far into D-way's history the import has read: when the latest version
# it has taken in was saved there, and which documents stood in it (a
# digest of their version ids). The next run takes the versions saved
# after that time — and the latest state again if its documents are no
# longer those, for what changes in D-way without a later save: an object
# deleted after the last send, a version dated before the one it follows.
#
# Kept apart from the chain: a version that changes nothing the record says
# writes no patch, and a mark read off the chain would stay behind it — the
# next run would take it again and, where a curator has edited the record
# since, write a patch putting the edit back.
class AddVersionMarkToDRASubmissions < ActiveRecord::Migration[8.1]
  def change
    change_table :dra_submissions, bulk: true do |t|
      t.datetime :version_saved_at
      t.string   :version_digest
    end
  end
end
