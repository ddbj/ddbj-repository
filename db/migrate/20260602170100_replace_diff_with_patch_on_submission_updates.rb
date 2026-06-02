class ReplaceDiffWithPatchOnSubmissionUpdates < ActiveRecord::Migration[8.1]
  def up
    remove_column :submission_updates, :diff

    add_column :submission_updates, :actor,                    :string
    add_column :submission_updates, :source,                   :integer, null: false, default: 0
    add_column :submission_updates, :patch,                    :binary,  null: false, default: ''
    add_column :submission_updates, :patch_canonical_version,  :integer, null: false, default: 1

    change_column_default :submission_updates, :patch, from: '', to: nil

    add_check_constraint :submission_updates, 'octet_length(patch) > 0', name: 'submission_updates_patch_nonempty'

    add_index :submission_updates, :actor, where: 'actor IS NOT NULL'
    add_index :submission_updates, [:submission_id, :created_at]
  end

  def down
    remove_index  :submission_updates, [:submission_id, :created_at]
    remove_index  :submission_updates, :actor

    remove_check_constraint :submission_updates, name: 'submission_updates_patch_nonempty'

    remove_column :submission_updates, :patch_canonical_version
    remove_column :submission_updates, :patch
    remove_column :submission_updates, :source
    remove_column :submission_updates, :actor

    add_column :submission_updates, :diff, :string
  end
end
