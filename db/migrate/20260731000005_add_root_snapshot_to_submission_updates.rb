class AddRootSnapshotToSubmissionUpdates < ActiveRecord::Migration[8.1]
  # Marks a patch that replaces the whole document (RFC 6902: `add` or
  # `replace` at path ""). Every earlier patch in the chain is then
  # irrelevant to the result, so replay can start here.
  #
  # That is what makes the importers' "self-heal forward" actually heal.
  # Today a poisoned patch stops `materialise_at` dead — and the snapshot
  # written afterwards never gets reached, because replay walks the chain
  # in order from `{}`. The record stays readable only through the cache,
  # which quietly hides that the chain can no longer reproduce it.
  #
  # Recorded rather than derived: deciding whether a patch resets the
  # document means parsing it, and parsing every patch to find out which
  # ones to skip would cost exactly what skipping them saves.
  #
  # Existing rows default to false, which is the conservative reading —
  # "do not skip anything" is current behaviour. They are not backfilled:
  # the migrated corpus is rebuilt from source, and until then the first
  # snapshot written by any writer restores replay on its own.
  def change
    add_column :submission_updates, :root_snapshot, :boolean, null: false, default: false

    add_index :submission_updates, [:submission_id, :id],
              where: 'root_snapshot',
              name:  'index_submission_updates_root_snapshots'
  end
end
