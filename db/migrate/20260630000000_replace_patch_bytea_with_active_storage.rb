class ReplacePatchByteaWithActiveStorage < ActiveRecord::Migration[8.1]
  # bytea has a ~1GB practical ceiling on Postgres. A first-import baseline
  # patch for a 100K-sample BS submission or any Trad genome assembly will
  # blow past that; deltas can also exceed it in pathological cases (TSV
  # rewrite of every sample). Both `submission_updates.patch` and
  # `submissions.cached_materialised_record` are moved to ActiveStorage
  # attachments so SeaweedFS absorbs the size, not Postgres.
  #
  # Pre-prod: no existing rows are preserved. Re-import populates BP/BS via
  # MigrationRun once the new shape lands. See
  # [[project-submission-update-patch-size-ceiling]].
  def change
    remove_check_constraint :submission_updates, name: 'submission_updates_patch_nonempty'
    remove_column :submission_updates, :patch, :binary, null: false

    remove_column :submissions, :cached_materialised_record, :binary
  end
end
